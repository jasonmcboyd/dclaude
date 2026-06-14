// Command dclaude-entrypoint is the container bootstrap for dclaude.
//
// It runs as the container's entrypoint: it prepares the environment (PATH, the
// unprivileged runtime user, git trust, a sanitized ~/.claude.json, init scripts) and
// then hands off to `claude`. It replaces the former shell (entrypoint.sh) and
// PowerShell (entrypoint.ps1) entrypoints with a single cross-platform binary that is
// shipped inside the runtime volume.
//
// All configuration is delivered by the launcher via DCLAUDE_* environment variables
// (see internal/bootstrap). Every positional argument is forwarded verbatim to
// `claude --dangerously-skip-permissions`.
package main

import (
	"os"

	"github.com/jasonmcboyd/dclaude/internal/bootstrap"
	"github.com/jasonmcboyd/dclaude/internal/platform"
)

// version is overridden at build time via -ldflags "-X main.version=<tag>".
var version = "dev"

func main() {
	log := bootstrap.NewLogger(os.Stderr)
	cfg := bootstrap.Load()
	log.Verbosef("dclaude-entrypoint %s (host_os=%q workspace=%q)", version, cfg.HostOS, cfg.Workspace)

	// Run performs the bootstrap and execs claude; it does not return on success.
	bootstrap.Run(cfg, platform.New(), log, os.Args[1:])
}
