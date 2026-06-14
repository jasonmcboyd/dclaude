//go:build windows

package bootstrap

// OS default paths used when the launcher does not supply the corresponding env var.
const (
	defaultRuntime    = `C:\dclaude-runtime`
	defaultWorkspace  = `C:\workspace`
	defaultClaudeHome = `C:/Users/ContainerAdministrator/.claude`
	defaultInitBase   = `C:/mnt/init.d`
)
