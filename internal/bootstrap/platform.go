package bootstrap

// Platform abstracts the OS-specific bootstrap operations. The Linux and Windows
// implementations live in the platform package and are selected at compile time by build
// tag, so each cross-compiled binary contains only its own platform's code.
type Platform interface {
	// SetupPATH configures PATH (and related env such as GIT_EXEC_PATH) for the runtime
	// tools, including the bundled-git fallback when the image lacks git.
	SetupPATH(cfg *Config)

	// EnsureUser creates the unprivileged runtime user when running as root. It is a
	// no-op on Windows and when not root. A non-nil error is fatal.
	EnsureUser(cfg *Config) error

	// MatchWorkspaceUID aligns the runtime user's UID to the workspace owner on a native
	// Linux host. It is a no-op on Windows and under Docker Desktop. Errors are best-effort.
	MatchWorkspaceUID(cfg *Config) error

	// ScriptExt is the init-script extension this platform executes (".sh" / ".ps1").
	ScriptExt() string

	// RunScript executes a single init.d script with the platform's shell.
	RunScript(cfg *Config, path string) error

	// LinkDockerCLI wires a provisioned Docker CLI into the container (best-effort).
	LinkDockerCLI(cfg *Config) error

	// Exec hands off to claude as the runtime user, replacing the current process where
	// the OS supports it. It returns only on failure.
	Exec(cfg *Config, claudeArgs []string) error
}
