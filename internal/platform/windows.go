//go:build windows

package platform

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/jasonmcboyd/dclaude/internal/bootstrap"
)

// New returns the Windows bootstrap platform.
//
// Phase 1 status: the Windows entrypoint port is a stub (see the roadmap, Phase 5). PATH
// and init-script wiring are in place so the binary compiles and the cross-platform
// steps run, but Exec returns an error until Windows parity lands — the launcher does not
// route Windows containers to this binary yet.
func New() bootstrap.Platform { return windowsPlatform{} }

type windowsPlatform struct{}

func (windowsPlatform) ScriptExt() string { return ".ps1" }

func (windowsPlatform) SetupPATH(cfg *bootstrap.Config) {
	sep := string(os.PathListSeparator)
	node := filepath.Join(cfg.Runtime, "node")
	mingit := filepath.Join(cfg.Runtime, "mingit", "cmd")
	_ = os.Setenv("PATH", node+sep+mingit+sep+os.Getenv("PATH"))
}

func (windowsPlatform) EnsureUser(cfg *bootstrap.Config) error        { return nil }
func (windowsPlatform) MatchWorkspaceUID(cfg *bootstrap.Config) error { return nil }

func (windowsPlatform) RunScript(cfg *bootstrap.Config, path string) error {
	cmd := exec.Command("powershell", "-NoProfile", "-File", path)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	cmd.Env = os.Environ()
	return cmd.Run()
}

func (windowsPlatform) LinkDockerCLI(cfg *bootstrap.Config) error { return nil }

func (windowsPlatform) Exec(cfg *bootstrap.Config, claudeArgs []string) error {
	return fmt.Errorf("windows entrypoint not yet implemented (roadmap Phase 5)")
}
