# dclaude

PowerShell module that runs Claude Code inside Docker containers, providing a security boundary so Claude can run with `--dangerously-skip-permissions`.

## Project Structure

```
src/
  dclaude.psm1          # Module loader (dot-sources Private/ and Public/, registers alias)
  dclaude.psd1          # Module manifest
  Public/               # 7 exported functions
  Private/              # 11 internal helper functions
Images/
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

Entrypoint scripts are mounted from the host module's `Images/` directory at `docker run` time (not baked into images). This means changes to entrypoints take effect immediately without any rebuild.

**Alpine limitation:** Alpine-based images (musl libc) are not currently supported. The runtime volume uses glibc-linked Node.js binaries.

### Container Mounting Strategy

- Workspace → mounted at the **host path** (translated for cross-platform: `C:\Users\jason\repos` → `/c/Users/jason/repos` on Linux containers), read-write
- Runtime volume → mounted read-only (Node.js + Claude Code)
- Entrypoint script → mounted read-only from host `Images/` directory
- `~/.claude` → `/mnt/host-claude` (staging path, not directly at `~/.claude`)
- Entrypoint creates **symlinks** from container's `~/.claude/` into the staging mount
- `projects` and `rules` directories are handled specially (not bulk-symlinked)

The host-path mounting strategy ensures that Docker volume commands from inside the container (sibling containers) use paths that are valid on the host Docker daemon. The `DCLAUDE_WORKSPACE` environment variable tells the entrypoint the container-side workspace path; it falls back to `/workspace` (Linux) or `C:\workspace` (Windows) for backward compatibility.

#### Cross-Platform Path Translation

When running Linux containers on a Windows host, `ConvertTo-ContainerPath` translates Windows paths to the Docker Desktop `/c/...` convention (lowercase drive letter, forward slashes, no colon). This is the same format Docker Desktop uses internally for bind mounts.

### Project History for /resume

Claude Code's `/resume` discovers sessions by scanning `~/.claude/projects/<key>/`. The project key inside a container is derived from the container-side workspace path (which now matches the translated host path).

The launcher (`Invoke-DClaude`) **bind-mounts** the host project directory directly at the container's project path. This is required because Claude Code's multi-worktree resume uses `readdir` with `{withFileTypes: true}`, which returns `isDirectory()=false` for symlinks. Bind mounts appear as real directories.

The entrypoint detects the existing bind mount and falls back to a symlink only if the mount isn't present.

### Project Key Derivation

The project key is derived from the workspace path by replacing all `/`, `\`, and `:` characters with `-`. This algorithm is used in three places and must stay in sync:

1. **Launcher** (`Resolve-ContainerPaths.ps1`): `$containerKey = $workspace -replace '[/\\:]', '-'`
2. **Linux entrypoint** (`entrypoint.sh`): `container_key=$(printf '%s' "$WORKSPACE" | sed 's/[/\\:]/-/g')`
3. **Windows entrypoint** (`entrypoint.ps1`): `$containerKey = $Workspace -replace '[/\\:]', '-'`

The host-side key (for locating the project dir on the host) is derived from the original host path. The container-side key is derived from the translated workspace path.

### Entrypoints

Both entrypoints (`.ps1` and `.sh`) are mounted from the host `Images/` directory and follow the same pattern:
1. Set up PATH to include the runtime volume's Node.js (and MinGit on Windows)
2. Create `claude` user if not exists (Linux only — stock images won't have it)
3. Symlink host `.claude` subdirs/files into container home (except `projects`, `rules`)
4. Create `rules/` as a real directory, symlink host rules in, generate `dclaude-context.md`
5. Detect project dir bind mount or create symlink fallback
6. Sanitize `.claude.json` (strip host paths, pre-accept workspace on Windows)
7. Run init scripts from `/mnt/init.d/` directories (user-common, user-image, project-common, project-image)
8. `exec claude --dangerously-skip-permissions`

**Known limitation (Windows):** The Windows entrypoint uses `& claude.cmd` rather than `exec` (which has no PowerShell equivalent). Claude runs as a child of PowerShell (PID 1), so `docker stop` signals may not propagate cleanly. This is a platform limitation, not a bug.

### `.claude.json` Sanitization Rules

Both entrypoints sanitize `.claude.json` before launching Claude Code. The canonical transformations are:

| Field | Action |
| --- | --- |
| `projects` | Delete (host paths), then re-create with container workspace path pre-accepted |
| `githubRepoPaths` | Delete (host-specific paths) |
| `officialMarketplaceAutoInstallAttempted` | Set to `true` (skip marketplace prompt) |
| `officialMarketplaceAutoInstalled` | Set to `true` (skip marketplace prompt) |

The Linux entrypoint reads from the bind-mounted `/mnt/host-claude.json` and writes to `/home/claude/.claude.json`. The Windows entrypoint reads from `~/.claude/.claude.json` (symlinked into the `.claude` directory mount) and writes to `~/.claude.json`.

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
