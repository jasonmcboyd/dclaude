package bootstrap

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/jasonmcboyd/dclaude/internal/initd"
	"github.com/jasonmcboyd/dclaude/internal/sanitize"
)

// Run executes the container bootstrap and hands off to claude. It does not return on
// success: the final exec replaces the process, or the process terminates via Fatalf.
//
// Each step's fatality is explicit. Best-effort steps log a warning and continue; the
// few load-bearing steps (runtime user, config parse, exec) are fatal.
func Run(cfg *Config, p Platform, log *Logger, claudeArgs []string) {
	p.SetupPATH(cfg)

	if os.Getenv("COLORTERM") == "" {
		_ = os.Setenv("COLORTERM", "truecolor")
	}

	if err := p.EnsureUser(cfg); err != nil {
		log.Fatalf("create runtime user: %v", err)
	}

	configureGit(cfg, log)

	if err := p.MatchWorkspaceUID(cfg); err != nil {
		log.Warnf("match workspace UID: %v", err)
	}

	sanitizeClaudeJSON(cfg, log)
	reportSessions(cfg, log)
	runInitScripts(cfg, p, log)

	if err := p.LinkDockerCLI(cfg); err != nil {
		log.Warnf("link docker CLI: %v", err)
	}

	if err := p.Exec(cfg, claudeArgs); err != nil {
		log.Fatalf("exec claude: %v", err)
	}
}

// configureGit trusts the workspace directory to avoid git "dubious ownership" errors.
// It writes to the runtime user's gitconfig so the entry survives the privilege drop.
func configureGit(cfg *Config, log *Logger) {
	if _, err := exec.LookPath("git"); err != nil {
		log.Warnf("git is not available; some Claude Code features may not work")
		return
	}
	cmd := exec.Command("git", "config", "-f", cfg.GitConfigPath(), "--add", "safe.directory", cfg.Workspace)
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Warnf("git safe.directory: %v: %s", err, strings.TrimSpace(string(out)))
	}
}

// sanitizeClaudeJSON reads the read-only host .claude.json, strips host-specific data,
// and writes the container-ready config. A corrupt source is fatal (claude must not
// launch with no trust); a missing source is skipped.
func sanitizeClaudeJSON(cfg *Config, log *Logger) {
	src := cfg.ClaudeJSONSource()
	data, err := os.ReadFile(src)
	if err != nil {
		if os.IsNotExist(err) {
			log.Verbosef("no .claude.json at %s; skipping sanitize", src)
			return
		}
		log.Warnf("read %s: %v", src, err)
		return
	}
	out, err := sanitize.Sanitize(data, cfg.Workspace, cfg.HostPath)
	if err != nil {
		log.Fatalf("sanitize .claude.json: %v", err)
	}
	if err := os.WriteFile(cfg.ClaudeJSONDest(), out, 0o600); err != nil {
		log.Warnf("write %s: %v", cfg.ClaudeJSONDest(), err)
	}
}

// reportSessions reports how many prior /resume sessions exist for this workspace.
func reportSessions(cfg *Config, log *Logger) {
	dir := cfg.ProjectDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		log.Warnf("no project dir found for key %q", cfg.ContainerKey())
		return
	}
	n := 0
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".jsonl") {
			n++
		}
	}
	log.Infof("Project dir with %d session(s)", n)
}

// runInitScripts executes the discovered init.d scripts, warning (not aborting) on any
// individual failure.
func runInitScripts(cfg *Config, p Platform, log *Logger) {
	results := initd.Run(cfg.InitDirs(), p.ScriptExt(), func(path string) error {
		log.Infof("Running init script: %s", filepath.Base(path))
		return p.RunScript(cfg, path)
	})
	for _, r := range results {
		if r.Err != nil {
			log.Warnf("init script %s failed: %v", filepath.Base(r.Script), r.Err)
		}
	}
}
