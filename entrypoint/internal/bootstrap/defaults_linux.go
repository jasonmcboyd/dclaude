//go:build linux

package bootstrap

// OS default paths used when the launcher does not supply the corresponding env var.
const (
	defaultRuntime    = "/opt/dclaude-runtime"
	defaultWorkspace  = "/workspace"
	defaultClaudeHome = "/home/claude/.claude"
	defaultInitBase   = "/mnt/init.d"
)
