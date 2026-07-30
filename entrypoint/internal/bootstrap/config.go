package bootstrap

import (
	"os"
	"path/filepath"
	"strings"
)

// Config is the resolved bootstrap contract: values the launcher passes via the
// environment, with OS-appropriate fallbacks for backward compatibility with older
// launchers. The OS defaults live in defaults_{linux,windows}.go.
type Config struct {
	Runtime    string // DCLAUDE_RUNTIME: runtime volume mount root
	Workspace  string // DCLAUDE_WORKSPACE: container-side workspace path (project-key source)
	HostPath   string // DCLAUDE_HOST_PATH: original host workspace path (MCP lookup key)
	ClaudeHome string // DCLAUDE_CLAUDE_HOME: the ~/.claude mount target inside the container
	HostOS     string // DCLAUDE_HOST_OS: windows|linux|macos (the scenario-3 seam)
	Contract   string // DCLAUDE_CONTRACT: launcher/binary contract version
	Verbose    bool   // DCLAUDE_VERBOSE
}

// Load reads the bootstrap contract from the environment, applying OS defaults.
func Load() *Config {
	return &Config{
		Runtime:    envOr("DCLAUDE_RUNTIME", defaultRuntime),
		Workspace:  envOr("DCLAUDE_WORKSPACE", defaultWorkspace),
		HostPath:   os.Getenv("DCLAUDE_HOST_PATH"),
		ClaudeHome: envOr("DCLAUDE_CLAUDE_HOME", defaultClaudeHome),
		HostOS:     os.Getenv("DCLAUDE_HOST_OS"),
		Contract:   os.Getenv("DCLAUDE_CONTRACT"),
		Verbose:    os.Getenv("DCLAUDE_VERBOSE") != "",
	}
}

// ClaudeJSONSource is the read-only host .claude.json delivered inside the ~/.claude mount.
func (c *Config) ClaudeJSONSource() string {
	return filepath.Join(c.ClaudeHome, ".claude.json")
}

// ClaudeJSONDest is the runtime config location claude reads: ~/.claude.json, the sibling
// of the .claude directory (i.e. the home directory's .claude.json).
func (c *Config) ClaudeJSONDest() string {
	return filepath.Join(filepath.Dir(c.ClaudeHome), ".claude.json")
}

// GitConfigPath is the runtime user's gitconfig (sibling of the .claude directory), used
// for the workspace safe.directory entry so it survives the privilege drop.
func (c *Config) GitConfigPath() string {
	return filepath.Join(filepath.Dir(c.ClaudeHome), ".gitconfig")
}

// ContainerKey derives the /resume project key from the workspace path by replacing
// '/', '\\' and ':' with '-'. This algorithm must stay in sync with the launcher.
func (c *Config) ContainerKey() string {
	return strings.NewReplacer("/", "-", "\\", "-", ":", "-").Replace(c.Workspace)
}

// ProjectDir is the per-project session directory scanned by /resume.
func (c *Config) ProjectDir() string {
	return filepath.Join(c.ClaudeHome, "projects", c.ContainerKey())
}

// InitDirs are the ordered init.d directories (user-common, user-image, project-common,
// project-image).
func (c *Config) InitDirs() []string {
	return []string{
		filepath.Join(defaultInitBase, "user-common"),
		filepath.Join(defaultInitBase, "user-image"),
		filepath.Join(defaultInitBase, "project-common"),
		filepath.Join(defaultInitBase, "project-image"),
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
