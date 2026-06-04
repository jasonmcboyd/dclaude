# dclaude

PowerShell module that runs Claude Code inside Docker containers, providing a security boundary so Claude can run with `--dangerously-skip-permissions`.

## Project Structure

```
src/
  dclaude.psm1          # Module loader (dot-sources Private/ and Public/, registers alias)
  dclaude.psd1          # Module manifest
  Public/               # 7 exported functions
  Private/              # 11 internal helper functions
Entrypoints/
  entrypoint.ps1        # Windows container init (mounted at runtime, not baked into images)
  entrypoint.sh         # Linux container init (mounted at runtime, not baked into images)
tests/
  Public/               # Pester 5 tests mirroring src/Public/
  Private/              # Pester 5 tests mirroring src/Private/
scripts/
  create-module-manifest.ps1  # CI: generate manifest for PSGallery publish
.github/
  workflows/
    publish-release.yml # CI/CD: publish to PSGallery on version tag push (v*)
```

## Testing

```powershell
# Run tests (requires Pester 5)
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path ./tests -Output Detailed
```

No build step is required. The module uses stock Docker images (e.g. `python:3.12-slim`,
`mcr.microsoft.com/dotnet/sdk:8.0`) and injects Node.js + Claude Code at runtime via a
named volume (`dclaude-runtime-{os}-v{version}`). The volume is lazily provisioned on
first use and reused across containers.

## Architecture

### Config Hierarchy

1. **User config** (`~/.dclaude/settings.json`) — global image registry
2. **Project config** (`.dclaude/settings.json`) — committed, team-shared
3. **Local overrides** (`settings.local.json` alongside either) — machine-specific, git-ignored

Merge is **shallow**: local replaces entire top-level properties from base.

### Runtime Volume

Instead of building custom Docker images, dclaude injects Node.js + Claude Code (+ MinGit on Windows) into any stock image via a versioned named volume:

- Volume name: `dclaude-runtime-{os}-v{version}` (version = module version from `dclaude.psd1`)
- Lazily provisioned on first use by `Initialize-RuntimeVolume.ps1`
- Mounted read-only at `/opt/dclaude-runtime` (Linux) or `C:\dclaude-runtime` (Windows)
- Stale volumes from previous module versions are cleaned up by `Remove-StaleRuntimeVolumes.ps1`
- The Docker CLI volume (`dclaude-docker-cli-*`) has a separate lifecycle, opt-in via `-DockerAccess`

Entrypoint scripts are mounted from the host module's `Entrypoints/` directory at `docker run` time (not baked into images). This means changes to entrypoints take effect immediately without any rebuild.

**Alpine limitation:** Alpine-based images (musl libc) are not currently supported. The runtime volume uses glibc-linked Node.js binaries.

### Container Mounting Strategy

- Workspace → mounted at the **host path** (translated for cross-platform: `C:\Users\jason\repos` → `/c/Users/jason/repos` on Linux containers), read-write
- Runtime volume → mounted read-only (Node.js + Claude Code)
- Entrypoint script → mounted read-only from host `Entrypoints/` directory
- `~/.claude` → mounted **directly** at the container's `~/.claude` (`/home/claude/.claude` on Linux, `C:/Users/ContainerAdministrator/.claude` on Windows), read-write
- `.claude.json` → Linux: nested read-only bind mount inside the `.claude` directory mount; Windows: symlinked into `~/.claude/` by `Initialize-DClaudeWindowsContainers`
- Linux cross-platform directories (`plugins/`, `session-env/`) → masked with tmpfs overlays to hide Windows-specific content

The direct mount approach ensures that Claude Code's atomic writes (write-temp, rename) work correctly — files stay on the bind-mounted filesystem with no symlinks to break. This is critical for credential persistence (e.g., MCP OAuth tokens in `.credentials.json`).

The host-path mounting strategy ensures that Docker volume commands from inside the container (sibling containers) use paths that are valid on the host Docker daemon. The `DCLAUDE_WORKSPACE` environment variable tells the entrypoint the container-side workspace path; it falls back to `/workspace` (Linux) or `C:\workspace` (Windows) for backward compatibility.

#### Container Context Awareness

A permanent rules file (`~/.claude/rules/dclaude-rules.md`) is installed on the host by the launcher on first run. It contains conditional instructions that reference `DCLAUDE_*` environment variables for dynamic context (host path, image name, volume mounts, env vars). This requires no runtime generation or cleanup on exit.

#### Cross-Platform Path Translation

When running Linux containers on a Windows host, `ConvertTo-ContainerPath` translates Windows paths to the Docker Desktop `/c/...` convention (lowercase drive letter, forward slashes, no colon). This is the same format Docker Desktop uses internally for bind mounts.

### Project History for /resume

Claude Code's `/resume` discovers sessions by scanning `~/.claude/projects/<key>/`. The project key inside a container is derived from the container-side workspace path (which now matches the translated host path).

The launcher (`Invoke-DClaude`) **bind-mounts** the host project directory directly at the container's project path. This is required because Claude Code's multi-worktree resume uses `readdir` with `{withFileTypes: true}`, which returns `isDirectory()=false` for symlinks. Bind mounts appear as real directories.

### Project Key Derivation

The project key is derived from the workspace path by replacing all `/`, `\`, and `:` characters with `-`. This algorithm is used in three places and must stay in sync:

1. **Launcher** (`Resolve-ContainerPaths.ps1`): `$containerKey = $workspace -replace '[/\\:]', '-'`
2. **Linux entrypoint** (`entrypoint.sh`): `container_key=$(printf '%s' "$WORKSPACE" | sed 's/[/\\:]/-/g')`
3. **Windows entrypoint** (`entrypoint.ps1`): `$containerKey = $Workspace -replace '[/\\:]', '-'`

The host-side key (for locating the project dir on the host) is derived from the original host path. The container-side key is derived from the translated workspace path.

### Entrypoints

Both entrypoints (`.ps1` and `.sh`) are mounted from the host `Entrypoints/` directory and follow the same pattern:
1. Set up PATH to include the runtime volume's Node.js (and MinGit on Windows)
2. Create `claude` user if not exists (Linux only — stock images won't have it)
3. Configure git safe.directory for the workspace
4. Sanitize `.claude.json` (strip host paths, pre-accept workspace, preserve MCP config)
5. Detect project dir bind mount and report session count
6. Run init scripts from `/mnt/init.d/` directories (user-common, user-image, project-common, project-image)
7. Link Docker CLI from provisioned volume (if `-DockerAccess` was used)
8. `exec claude --dangerously-skip-permissions`

**Known limitation (Windows):** The Windows entrypoint uses `& claude.cmd` rather than `exec` (which has no PowerShell equivalent). Claude runs as a child of PowerShell (PID 1), so `docker stop` signals may not propagate cleanly. This is a platform limitation, not a bug.

### `.claude.json` Sanitization Rules

Both entrypoints sanitize `.claude.json` before launching Claude Code. The canonical transformations are:

| Field | Action |
| --- | --- |
| `projects` | Delete (host paths), then re-create with container workspace path pre-accepted. MCP fields (`mcpServers`, `mcpContextUris`, `enabledMcpjsonServers`, `disabledMcpjsonServers`) are preserved from the matching host project entry. |
| `githubRepoPaths` | Delete (host-specific paths) |
| `officialMarketplaceAutoInstallAttempted` | Set to `true` (skip marketplace prompt) |
| `officialMarketplaceAutoInstalled` | Set to `true` (skip marketplace prompt) |

The Linux entrypoint reads from `~/.claude/.claude.json` (inside the direct mount) and writes the sanitized version to `~/.claude.json`. The Windows entrypoint reads from `~/.claude/.claude.json` and writes to `~/.claude.json` (only if the destination doesn't already exist).

## Platform Parity

Every bug fix or feature must be applied to **all three container targets**:

1. **Windows containers on Windows** (`entrypoint.ps1`)
2. **Linux containers on Windows** (`entrypoint.sh`)
3. **Linux containers on Linux** (`entrypoint.sh`)

The Windows and Linux entrypoints implement the same logic in different languages. When changing one, always check if the other needs the same change — but note that achieving the same effective behavior may require a different implementation on each platform (e.g., different permission models, path formats, symlink semantics). The launcher (`Invoke-DClaude.ps1`) already branches on `$containerOS` for path differences.

## Conventions

- Functions use standard PowerShell `Verb-Noun` naming with `DClaude` noun prefix
- Error handling: `Write-Error` + early return (not `throw`), except `throw` is acceptable for unrecoverable parse errors (corrupted JSON, malformed config files)
- Tests mock `docker` and filesystem; use Pester's `$TestDrive` for isolation
- Volumes default to read-only (`:ro`); explicit `:rw` required for write access
- Environment variables `%VAR%` are expanded at runtime in volume specs
- The `claude` user is created by the Linux entrypoint at **UID 1000** for consistent file ownership
