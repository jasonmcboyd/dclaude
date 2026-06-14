//go:build windows

package platform

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/jasonmcboyd/dclaude/entrypoint/internal/bootstrap"
)

// New returns the Windows bootstrap platform.
func New() bootstrap.Platform { return windowsPlatform{} }

type windowsPlatform struct{}

func (windowsPlatform) ScriptExt() string { return ".ps1" }

func (windowsPlatform) SetupPATH(cfg *bootstrap.Config) {
	sep := string(os.PathListSeparator)
	node := filepath.Join(cfg.Runtime, "node")
	mingit := filepath.Join(cfg.Runtime, "mingit", "cmd")
	_ = os.Setenv("PATH", node+sep+mingit+sep+os.Getenv("PATH"))
}

// EnsureUser and MatchWorkspaceUID are no-ops on Windows: containers run as the image's
// default user (ContainerAdministrator) and ownership is governed by ACLs, not UIDs.
func (windowsPlatform) EnsureUser(cfg *bootstrap.Config) error        { return nil }
func (windowsPlatform) MatchWorkspaceUID(cfg *bootstrap.Config) error { return nil }

func (windowsPlatform) RunScript(cfg *bootstrap.Config, path string) error {
	cmd := exec.Command("powershell", "-NoProfile", "-File", path)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	cmd.Env = os.Environ()
	return cmd.Run()
}

func (windowsPlatform) LinkDockerCLI(cfg *bootstrap.Config) error {
	if _, err := exec.LookPath("docker"); err == nil {
		return nil // image already provides docker
	}
	const cliDir = `C:\docker-cli`
	if !fileExists(filepath.Join(cliDir, "docker.exe")) {
		return nil
	}
	// Put the provisioned CLI on PATH (Windows can't symlink an exe onto PATH the way Linux
	// does at /usr/local/bin), then symlink the plugins into the user's docker config.
	_ = os.Setenv("PATH", cliDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	entries, err := os.ReadDir(filepath.Join(cliDir, "cli-plugins"))
	if err != nil {
		return nil
	}
	pluginDst := filepath.Join(os.Getenv("USERPROFILE"), ".docker", "cli-plugins")
	_ = os.MkdirAll(pluginDst, 0o755)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		_ = os.Symlink(filepath.Join(cliDir, "cli-plugins", e.Name()), filepath.Join(pluginDst, e.Name()))
	}
	return nil
}

// Exec launches claude and propagates its exit code. Windows has no execve, so the binary
// stays alive as claude's parent (the same PID-1-child limitation the PowerShell entrypoint
// had — `docker stop` signals may not propagate cleanly). It returns only if claude cannot
// be started; on a clean run it terminates the process with claude's exit code.
func (windowsPlatform) Exec(cfg *bootstrap.Config, claudeArgs []string) error {
	claudePath, err := exec.LookPath("claude")
	if err != nil {
		return fmt.Errorf("claude not found on PATH: %w", err)
	}
	args := append([]string{"--dangerously-skip-permissions"}, claudeArgs...)
	cmd := exec.Command(claudePath, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	cmd.Env = os.Environ()

	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			os.Exit(exitErr.ExitCode())
		}
		return fmt.Errorf("run claude: %w", err)
	}
	os.Exit(0)
	return nil // unreachable
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
