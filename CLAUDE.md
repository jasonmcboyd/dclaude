# dclaude

PowerShell module that runs Claude Code inside Docker containers, providing a security boundary so Claude can run with `--dangerously-skip-permissions`.

## Project Structure

```
src/
  dclaude.psm1          # Module loader (dot-sources Private/ and Public/, registers alias)
  dclaude.psd1          # Module manifest
  Public/               # 7 exported functions
  Private/              # 7 internal helper functions
Images/
  Dockerfile            # Windows container image
  Dockerfile.linux      # Linux container image (shared across pwsh, dotnet-core, etc.)
  entrypoint.ps1        # Windows container init
  entrypoint.sh         # Linux container init
tests/
  Public/               # Pester 5 tests mirroring src/Public/
  Private/              # Pester 5 tests mirroring src/Private/
scripts/
  build-image.ps1       # Build Docker images (-Name pwsh|dotnet-core|dotnet-framework or -All)
  create-module-manifest.ps1  # CI: generate manifest for PSGallery publish
```

## Building and Testing

```powershell
# Build Docker images (auto-detects Windows/Linux Docker mode)
./scripts/build-image.ps1 -Name pwsh
./scripts/build-image.ps1 -All

# Run tests (requires Pester 5)
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path ./tests -Output Detailed
```

## Architecture

### Config Hierarchy

1. **User config** (`~/.dclaude/settings.json`) — global image registry
2. **Project config** (`.dclaude/settings.json`) — committed, team-shared
3. **Local overrides** (`settings.local.json` alongside either) — machine-specific, git-ignored

Merge is **shallow**: local replaces entire top-level properties from base.

### Container Mounting Strategy

- Workspace → `/workspace` (Linux) or `C:/workspace` (Windows), read-write
- `~/.claude` → `/mnt/host-claude` (staging path, not directly at `~/.claude`)
- Entrypoint creates **symlinks** from container's `~/.claude/` into the staging mount
- `projects` and `rules` directories are handled specially (not bulk-symlinked)

### Project History for /resume

Claude Code's `/resume` discovers sessions by scanning `~/.claude/projects/<key>/`. The project key inside a container is `-workspace` (Linux) or `C--workspace` (Windows).

The launcher (`Invoke-DClaude`) **bind-mounts** the host project directory directly at the container's project path. This is required because Claude Code's multi-worktree resume uses `readdir` with `{withFileTypes: true}`, which returns `isDirectory()=false` for symlinks. Bind mounts appear as real directories.

The entrypoint detects the existing bind mount and falls back to a symlink only if the mount isn't present.

### Entrypoints

Both entrypoints (`.ps1` and `.sh`) follow the same pattern:
1. Symlink host `.claude` subdirs/files into container home (except `projects`, `rules`)
2. Create `rules/` as a real directory, symlink host rules in, generate `dclaude-context.md`
3. Detect project dir bind mount or create symlink fallback
4. Sanitize `.claude.json` (strip host paths, pre-accept workspace on Windows)
5. `exec claude --dangerously-skip-permissions`

## Platform Parity

Every bug fix or feature must be applied to **all three container targets**:

1. **Windows containers on Windows** (`Dockerfile` + `entrypoint.ps1`)
2. **Linux containers on Windows** (`Dockerfile.linux` + `entrypoint.sh`)
3. **Linux containers on Linux** (`Dockerfile.linux` + `entrypoint.sh`)

The Windows and Linux entrypoints implement the same logic in different languages. When changing one, always check if the other needs the same change — but note that achieving the same effective behavior may require a different implementation on each platform (e.g., different permission models, path formats, symlink semantics). The launcher (`Invoke-DClaude.ps1`) already branches on `$containerOS` for path differences.

## Conventions

- Functions use standard PowerShell `Verb-Noun` naming with `DClaude` noun prefix
- Error handling: `Write-Error` + early return (not `throw`)
- Tests mock `docker` and filesystem; use Pester's `$TestDrive` for isolation
- Volumes default to read-only (`:ro`); explicit `:rw` required for write access
- Environment variables `%VAR%` are expanded at runtime in volume specs
- The `claude` user in Linux images is pinned to **UID 1000** for consistent file ownership
