//go:build linux

package platform

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/jasonmcboyd/dclaude/entrypoint/internal/bootstrap"
)

// New returns the Linux bootstrap platform.
func New() bootstrap.Platform { return linuxPlatform{} }

type linuxPlatform struct{}

func (linuxPlatform) ScriptExt() string { return ".sh" }

func (linuxPlatform) SetupPATH(cfg *bootstrap.Config) {
	sep := string(os.PathListSeparator)
	// node is prepended (highest priority); the bundled git fallback is appended (lowest),
	// used only when the image provides no git of its own.
	path := filepath.Join(cfg.Runtime, "node", "bin") + sep + os.Getenv("PATH")
	if _, err := exec.LookPath("git"); err != nil {
		gitBin := filepath.Join(cfg.Runtime, "git", "bin")
		if isExecutable(filepath.Join(gitBin, "git")) {
			path += sep + gitBin
			_ = os.Setenv("GIT_EXEC_PATH", filepath.Join(cfg.Runtime, "git", "libexec", "git-core"))
		}
	}
	_ = os.Setenv("PATH", path)
}

func (linuxPlatform) EnsureUser(cfg *bootstrap.Config) error {
	if os.Geteuid() != 0 {
		return nil // not root: cannot (and need not) create users
	}
	if userExists("claude") {
		ensureHome()
		return nil
	}
	// Evict a non-claude UID 1000 squatter (e.g. 'app' in the .NET SDK images).
	if name := userNameByID(1000); name != "" && name != "claude" {
		_ = run("userdel", name)
	}
	if err := run("useradd", "-m", "-u", "1000", "claude"); err != nil {
		if err2 := run("adduser", "-D", "-u", "1000", "claude"); err2 != nil {
			return fmt.Errorf("useradd failed (%v) and adduser fallback failed (%v)", err, err2)
		}
	}
	ensureHome()
	return nil
}

func ensureHome() { _ = os.MkdirAll("/home/claude", 0o755) }

func (linuxPlatform) MatchWorkspaceUID(cfg *bootstrap.Config) error {
	if os.Geteuid() != 0 {
		return nil
	}
	// Scenario seam: UID matching is only meaningful on a real POSIX host bind mount. On
	// Docker Desktop (Windows/macOS host) ownership is synthesized, so skip it.
	if cfg.HostOS == "windows" || cfg.HostOS == "macos" {
		return nil
	}
	// TODO(scenario-3): on a native Linux host (cfg.HostOS == "linux") the logic below
	// replicates the existing, untested entrypoint.sh behavior verbatim and ships no new
	// behavior. Future work: handle root-owned workspaces (ws_uid=0) and images lacking
	// usermod, or move to a launcher-side `--user $(id -u):$(id -g)`.

	info, err := os.Stat(cfg.Workspace)
	if err != nil {
		return nil // best-effort: leave claude at UID 1000
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return nil
	}
	uid := int(st.Uid)
	if uid == 0 || uid == 1000 {
		return nil // 0 => Docker Desktop 9P (synthesized); 1000 => already aligned
	}
	if err := run("usermod", "-u", strconv.Itoa(uid), "claude"); err != nil {
		return fmt.Errorf("usermod -u %d claude: %w", uid, err)
	}
	return nil
}

func (linuxPlatform) RunScript(cfg *bootstrap.Config, path string) error {
	shell := "sh"
	if p, err := exec.LookPath("bash"); err == nil {
		shell = p
	}
	cmd := exec.Command(shell, path)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	cmd.Env = os.Environ()
	return cmd.Run()
}

func (linuxPlatform) LinkDockerCLI(cfg *bootstrap.Config) error {
	if _, err := exec.LookPath("docker"); err == nil {
		return nil // image already provides docker
	}
	const cli = "/opt/docker-cli/docker"
	if !isExecutable(cli) {
		return nil
	}
	if err := os.Symlink(cli, "/usr/local/bin/docker"); err != nil && !os.IsExist(err) {
		return err
	}
	entries, err := os.ReadDir("/opt/docker-cli/cli-plugins")
	if err != nil {
		return nil
	}
	_ = os.MkdirAll("/usr/local/lib/docker/cli-plugins", 0o755)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		src := filepath.Join("/opt/docker-cli/cli-plugins", e.Name())
		dst := filepath.Join("/usr/local/lib/docker/cli-plugins", e.Name())
		_ = os.Symlink(src, dst)
	}
	return nil
}

func (linuxPlatform) Exec(cfg *bootstrap.Config, claudeArgs []string) error {
	claudePath, err := exec.LookPath("claude")
	if err != nil {
		return fmt.Errorf("claude not found on PATH: %w", err)
	}
	args := append([]string{"--dangerously-skip-permissions"}, claudeArgs...)

	if os.Geteuid() != 0 {
		// Already unprivileged: exec claude directly.
		return syscall.Exec(claudePath, append([]string{"claude"}, args...), withHome(os.Environ(), "/home/claude"))
	}

	// Running as root: grant docker socket access, fix ownership, then drop privileges.
	addDockerGroup()
	fixHomeOwnership(cfg)

	// Prefer setpriv: it preserves the ambient capabilities Claude Code needs for correct
	// file timestamps under WSL2. Fall back to su where setpriv is unavailable.
	if setpriv, err := exec.LookPath("setpriv"); err == nil {
		argv := []string{
			"setpriv", "--reuid=claude", "--regid=claude", "--init-groups",
			"--inh-caps=+fowner,+dac_override", "--ambient-caps=+fowner,+dac_override",
			"--no-new-privs", "--",
			"env", "PATH=" + os.Getenv("PATH"), "HOME=/home/claude", "claude",
		}
		argv = append(argv, args...)
		return syscall.Exec(setpriv, argv, os.Environ())
	}

	su, err := exec.LookPath("su")
	if err != nil {
		return fmt.Errorf("neither setpriv nor su is available to drop privileges: %w", err)
	}
	inner := "export PATH='" + os.Getenv("PATH") + "' HOME='/home/claude'; exec " + shellQuote(append([]string{"claude"}, args...))
	return syscall.Exec(su, []string{"su", "-s", "/bin/sh", "claude", "-c", inner}, os.Environ())
}

// addDockerGroup gives the claude user access to a mounted Docker socket by joining a
// group that owns it. Best-effort.
func addDockerGroup() {
	const sock = "/var/run/docker.sock"
	info, err := os.Stat(sock)
	if err != nil {
		return
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return
	}
	gid := strconv.FormatUint(uint64(st.Gid), 10)
	if !commandSucceeds("getent", "group", gid) {
		_ = run("groupadd", "-g", gid, "docker-host")
	}
	_ = run("usermod", "-aG", gid, "claude")
}

// fixHomeOwnership chowns the runtime user's home, skipping the read-only .claude.json
// bind mount (which cannot be chowned). Best-effort; never aborts the bootstrap.
func fixHomeOwnership(cfg *bootstrap.Config) {
	home := filepath.Dir(cfg.ClaudeHome)
	script := fmt.Sprintf("find %s -path %s -prune -o -exec chown -h claude:claude {} + || true",
		shellQuoteArg(home), shellQuoteArg(cfg.ClaudeJSONSource()))
	_ = exec.Command("sh", "-c", script).Run()
}

// --- small process helpers ---

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	return cmd.Run()
}

func commandSucceeds(name string, args ...string) bool {
	return exec.Command(name, args...).Run() == nil
}

func userExists(name string) bool { return commandSucceeds("id", name) }

func userNameByID(uid int) string {
	out, err := exec.Command("getent", "passwd", strconv.Itoa(uid)).Output()
	if err != nil {
		return ""
	}
	line := strings.TrimSpace(string(out))
	if line == "" {
		return ""
	}
	return strings.SplitN(line, ":", 2)[0]
}

func isExecutable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Mode()&0o111 != 0
}

// withHome returns env with HOME set to home (replacing any existing HOME).
func withHome(env []string, home string) []string {
	out := make([]string, 0, len(env)+1)
	found := false
	for _, e := range env {
		if strings.HasPrefix(e, "HOME=") {
			out = append(out, "HOME="+home)
			found = true
			continue
		}
		out = append(out, e)
	}
	if !found {
		out = append(out, "HOME="+home)
	}
	return out
}

func shellQuoteArg(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func shellQuote(args []string) string {
	quoted := make([]string, len(args))
	for i, a := range args {
		quoted[i] = shellQuoteArg(a)
	}
	return strings.Join(quoted, " ")
}
