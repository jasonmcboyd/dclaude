# dclaude

Run Claude Code with `--dangerously-skip-permissions` inside Docker containers so the container itself is the security boundary. Your project, Claude config, API key, and configurable volumes are mounted into an isolated container where Claude can operate freely without risk to your host system.

## Container Platform Support

dclaude supports three deployment configurations:

| Host OS | Container OS | Notes |
|---|---|---|
| Windows | Windows | Full Windows container support, including .NET Framework workloads |
| Windows | Linux | Docker Desktop Linux container mode; recommended for most projects |
| Linux / macOS | Linux | Native Linux containers |

The launcher auto-detects the current Docker container mode via `docker info` and selects the matching platform block from your image configuration. You can maintain separate image tags and volume mounts for Windows and Linux containers under the same image key — switching modes is transparent to project config.

Windows container support is particularly useful for workloads that require the Windows container filesystem, COM components, .NET Framework (not just .NET), or Windows-specific toolchains. Linux containers on a Windows host (via Docker Desktop) are otherwise recommended and require no additional setup.

## Prerequisites

- Docker (Windows, macOS, or Linux)
- PowerShell 5.1 or later
- An API key or cloud credentials: `ANTHROPIC_API_KEY` for direct API access, or Vertex AI / Bedrock environment variables for cloud-hosted models
- Claude config at `~/.claude` (created by running `claude` once on the host)

### Windows Containers Setup

Windows containers cannot bind-mount individual files, only directories. Claude Code stores `~/.claude.json` separately from the `~/.claude/` directory, so a one-time setup is required to move the file inside the directory and create a symlink at the original location.

**1. Enable Developer Mode** (required for symlinks without elevation):

- Settings > Privacy & Security > For developers > Developer Mode
- Or from an elevated PowerShell:
  ```powershell
  reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1
  ```
- Verify: `Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense'` should return `1`

**2. Run the initialization command:**

```powershell
Initialize-DClaudeWindowsContainers
```

This copies `~/.claude.json` into `~/.claude/.claude.json`, then replaces the original with a symlink pointing into the directory. Host Claude Code continues to work transparently through the symlink. The file is now carried into containers via the existing `~/.claude/` directory mount.

This step is only required once. If you skip it, `dclaude` will display an error when running with Windows containers.

> **Note:** This is not required for Linux containers, even on a Windows host. Linux containers on Docker Desktop for Windows can bind-mount individual files without issue.

## Installation

**From PowerShell Gallery:**

```powershell
Install-Module dclaude
```

**From source:**

```powershell
git clone https://github.com/jasonboyd/dclaude.git
Import-Module ./dclaude/src/dclaude.psd1
```

## Quick Start

```powershell
# Run in the current directory using a direct image tag
Invoke-DClaude -Image dclaude-pwsh:latest

# Same thing using the alias and an image key defined in your user config
dclaude -ImageKey pwsh

# Run in a specific directory and pass arguments to Claude
dclaude -ImageKey dotnet -Path ~/repos/myproject -- --resume
```

If the current directory has a project config pointing at a registered image, you can invoke with no parameters:

```powershell
# Register an image in your global config
Add-DClaudeImage -Name pwsh -Tag dclaude-pwsh:latest -Platform Windows

# Create a project config referencing it
# .dclaude/settings.json: { "imageKey": "pwsh" }

# Then just run
dclaude
```

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Image` | `string` | Yes (ByImage set) | Docker image tag to run directly. Mutually exclusive with `-ImageKey`. |
| `-ImageKey` | `string` | Yes (ByImageKey set) | Key defined in `~/.dclaude/settings.json` that resolves to an image tag and optional volume mounts. Mutually exclusive with `-Image`. |
| `-Path` | `string` | No | Directory to mount as the workspace. Defaults to the current directory. |
| `-ClaudeConfigPath` | `string` | No | Path to the Claude config directory to mount into the container. Defaults to `~/.claude`. |
| `-ClaudeArgs` | `string[]` | No | Any additional arguments passed through to the `claude` entrypoint inside the container (e.g., `--resume`). Use `--` to separate from dclaude parameters. |
| `-DockerAccess` | `switch` | No | Mounts the Docker socket (Linux) or named pipe (Windows) into the container, allowing Claude to run Docker commands. See [Docker Access](#docker-access) below. |

When neither `-Image` nor `-ImageKey` is specified, the image is resolved from the project config file (`.dclaude/settings.json`) in the working directory.

## Configuration

dclaude uses a three-tier configuration hierarchy. The **user config** defines a global image registry that applies across all projects. The **project config** is committed to source control so the whole team uses the same image without coordination. **Local overrides** let individual developers customize settings per-machine (a different image variant, extra volume mounts) without touching the committed file or causing merge conflicts. Each tier is optional — you only need the layers that add value for your workflow.

### User Config — `~/.dclaude/settings.json`

Defines named images and their per-platform volume mounts. Lives in your home directory and applies across all projects.

```json
{
  "defaultImageKey": "pwsh",
  "envPassthrough": ["AZURE_DEVOPS_PAT"],
  "commonVolumes": {
    "windows": ["%USERPROFILE%\\.nuget:C:/Users/ContainerAdministrator/.nuget"],
    "linux": ["%HOME%/.nuget:/root/.nuget"]
  },
  "images": {
    "pwsh": {
      "windows": {
        "tag": "dclaude-pwsh:latest"
      },
      "linux": {
        "tag": "dclaude-pwsh-linux:latest"
      }
    },
    "vertex": {
      "linux": {
        "tag": "python:3.12-slim",
        "env": {
          "CLOUD_ML_REGION": "us-east1",
          "ANTHROPIC_VERTEX_PROJECT_ID": "my-project"
        }
      }
    },
    "dotnet-core": {
      "windows": {
        "tag": "dclaude-dotnet-core:latest",
        "envPassthrough": ["NUGET_*", "VSS_NUGET_*"]
      },
      "linux": {
        "tag": "dclaude-dotnet-core-linux:latest",
        "envPassthrough": ["NUGET_*"]
      }
    }
  }
}
```

Each key under `images` is an image name you can pass to `-ImageKey`. The value is an object with one or more platform keys:

| Field | Required | Description |
|---|---|---|
| `defaultImageKey` | No | Default image key used when no image is specified by `-Image`, `-ImageKey`, or project config. Allows `dclaude` to run with zero arguments from any directory. |
| `commonVolumes` | No | Volume mounts applied to **all** images. Either an array of mount strings, or an object with `windows`/`linux` keys for OS-specific mounts. Mounted read-only by default. |
| `envPassthrough` | No | Array of environment variable names or glob patterns forwarded to **all** images. `ANTHROPIC_*`, `CLAUDE_CODE_*`, and `CLOUD_ML_*` are always forwarded regardless of this setting. |
| `images.<name>.windows` | No* | Windows platform configuration. |
| `images.<name>.linux` | No* | Linux platform configuration. |
| `images.<name>.<platform>.tag` | Yes | Docker image tag to run. |
| `images.<name>.<platform>.volumes` | No | Array of volume mounts in `host:container` format. Mounted read-only by default; append `:rw` to make writable. Environment variables are expanded at runtime via .NET's `ExpandEnvironmentVariables`. Use `%VAR%` syntax — this works cross-platform. |
| `images.<name>.<platform>.env` | No | Object of static environment variables injected into the container (e.g., `{"CLOUD_ML_REGION": "us-east1"}`). Use for constants that don't exist on the host — for forwarding host variables, use `envPassthrough` instead. |
| `images.<name>.<platform>.envPassthrough` | No | Array of environment variable names or glob patterns (e.g. `NUGET_*`) to forward from the host into the container. Merged with global `envPassthrough`. |

*At least one platform must be defined per entry. `Invoke-DClaude` auto-detects the current Docker container OS and selects the matching platform.

### Project Config — `.dclaude/settings.json`

Place this file in a project directory to set the default image for that project. Committed to source control so the whole team uses the same image.

```json
{
  "imageKey": "dotnet-core"
}
```

Or with a direct image tag and project-specific volumes:

```json
{
  "image": "my-custom:latest",
  "volumes": ["./data:/workspace/data"]
}
```

| Field | Description |
|---|---|
| `image` | Direct Docker image tag. Takes precedence over `imageKey`. |
| `imageKey` | References a key in the user config `images` map. The correct platform (Windows/Linux) is selected automatically based on the current Docker mode. |
| `volumes` | Project-specific volume mounts added alongside any image-level volumes from the user config. Mounted read-only by default; append `:rw` to make writable. |

### Local Overrides — `settings.local.json`

Both the user config (`~/.dclaude/`) and project config (`.dclaude/`) directories support a `settings.local.json` file that overrides values from `settings.json`. Local files are never committed — they let you customize settings per-machine without affecting the shared configuration.

When both files exist in the same directory, properties from `settings.local.json` are shallow-merged on top of `settings.json`. For example, to override the project image on your local machine:

**`.dclaude/settings.json`** (committed):
```json
{
  "imageKey": "dotnet-core"
}
```

**`.dclaude/settings.local.json`** (git-ignored):
```json
{
  "imageKey": "pwsh",
  "volumes": ["/extra/data:/workspace/data"]
}
```

The effective config would use the `pwsh` image key and add the extra volume mount. The `settings.local.json` file is excluded via both the repo `.gitignore` and the global gitignore.

When `dclaude` runs with no parameters, image resolution follows this priority order:

1. `-Image` parameter
2. `-ImageKey` parameter
3. `image` field in project config
4. `imageKey` field in project config (resolved through user config)
5. `defaultImageKey` field in user config (`~/.dclaude/settings.json`)

## Managing Images

Use `Add-DClaudeImage`, `Get-DClaudeImage`, and `Remove-DClaudeImage` to manage image entries without editing JSON files directly.

```powershell
# Add a Windows image
Add-DClaudeImage -Name dotnet-core -Tag dclaude-dotnet-core:latest -Platform Windows

# Add a Linux variant for the same image
Add-DClaudeImage -Name dotnet-core -Tag dclaude-dotnet-core-linux:latest -Platform Linux

# Add with volume mounts
Add-DClaudeImage -Name dotnet-core -Tag dclaude-dotnet-core:latest -Platform Windows -Volumes '%USERPROFILE%\.nuget:C:/Users/ContainerAdministrator/.nuget'

# List all images
Get-DClaudeImage

# List a specific image
Get-DClaudeImage -Name dotnet-core

# Remove a specific platform
Remove-DClaudeImage -Name dotnet-core -Platform Linux

# Remove an entire image entry (all platforms)
Remove-DClaudeImage -Name dotnet-core
```

| Parameter | Type | Description |
|---|---|---|
| `-Name` | `string` | Image entry name (key in the `images` map). Required for Add and Remove; optional for Get. |
| `-Tag` | `string` | Docker image tag. Required for Add. |
| `-Volumes` | `string[]` | Volume mounts in `host:container` format. Optional for Add. |
| `-Platform` | `Windows\|Linux` | Target platform for the image entry. Required for Add; optional for Remove (omit to remove all platforms). |
| `-Force` | `switch` | Overwrite an existing platform entry without removing it first. Only for Add. |

These commands manage the global image registry at `~/.dclaude/settings.json`.

## Managing Project Config

Use `Set-DClaudeProject` and `Get-DClaudeProject` to manage project-local overrides (`.dclaude/settings.local.json`) without editing JSON directly. To create the shared project config (`.dclaude/settings.json`), edit the file directly.

```powershell
# Set project to use a registered image key
Set-DClaudeProject -ImageKey pwsh

# Or set a direct image tag with volumes
Set-DClaudeProject -Image my-custom:latest -Volumes './data:/workspace/data'

# View current project config
Get-DClaudeProject

# Set project config in a different directory
Set-DClaudeProject -ImageKey dotnet-core -Path ~/repos/other-project
```

| Parameter | Type | Description |
|---|---|---|
| `-ImageKey` | `string` | References a key in the global image registry. Mutually exclusive with `-Image`. |
| `-Image` | `string` | Direct Docker image tag. Mutually exclusive with `-ImageKey`. |
| `-Volumes` | `string[]` | Project-specific volume mounts in `host:container` format. Optional. |
| `-Path` | `string` | Target project directory. Defaults to the current directory. |

## Images

dclaude works with any stock Docker image — no custom Dockerfiles required. Node.js and Claude Code are injected at runtime via a versioned named volume that is lazily provisioned on first use.

```powershell
# Use any stock image directly
Invoke-DClaude -Image 'python:3.12-slim'
Invoke-DClaude -Image 'mcr.microsoft.com/dotnet/sdk:8.0'
Invoke-DClaude -Image 'mcr.microsoft.com/powershell:lts'
```

The runtime volume contains Node.js and Claude Code (plus MinGit on Windows). It is mounted read-only and shared across containers running the same module version. Stale volumes from previous versions are cleaned up automatically.

Alpine-based images (e.g. `python:3.12-alpine`) are not currently supported — use the standard variants instead (e.g. `python:3.12-slim`).

If you need additional tools (az, kubectl, terraform, etc.), install them in your image or use an [init script](#init-scripts).

## CI/CD and Releases

The module is published to [PowerShell Gallery](https://www.powershellgallery.com/packages/dclaude) via GitHub Actions. Pushing a version tag (e.g. `v0.15.1`) triggers the `publish-release.yml` workflow, which generates the module manifest and publishes to PSGallery automatically.

## What Gets Mounted

Every container run by `dclaude` receives these mounts automatically:

| Host path | Container path (Windows) | Container path (Linux) | Mode | Purpose |
|---|---|---|---|---|
| `$Path` (working dir) | Host path as-is | Translated host path (e.g. `/c/Users/you/repos/myproject`) | read-write | Project files |
| `~/.claude` | `C:/mnt/host-claude` | `/mnt/host-claude` | read-write | Claude settings staging; entrypoint symlinks into `~/.claude` |
| Runtime volume | `C:\dclaude-runtime` | `/opt/dclaude-runtime` | read-only | Node.js + Claude Code |
| Entrypoint script | `C:\mnt\dclaude` (directory) | `/mnt/dclaude/entrypoint.sh` (file) | read-only | Container init from host module |

Additional volume mounts are layered from three sources: `commonVolumes` from user config (applied to all images), image-level `volumes` from the matching platform block, and project-level `volumes` from the project config. All are applied together and are **read-only by default**. To make a volume writable, append `:rw` to the mount string (e.g., `"/path/on/host:/path/in/container:rw"`). Environment variables matching `ANTHROPIC_*`, `CLAUDE_CODE_*`, and `CLOUD_ML_*` are always forwarded; additional patterns can be configured via `envPassthrough`. The container OS is auto-detected from `docker info`; the matching platform block is selected and container paths are set accordingly.

### Session Continuity and `/resume`

Claude Code's `/resume` command discovers previous sessions by scanning `~/.claude/projects/<key>/` for `.jsonl` conversation files. The project key is derived from the workspace path, so the container-side workspace path must match what Claude Code expects.

dclaude bind-mounts the host project directory directly into the container at the correct path. This is a bind mount, not a symlink. The distinction matters: Claude Code's session discovery uses `readdir` with `{withFileTypes: true}`, and that API returns `isDirectory() = false` for symlinks — symlinked project directories are silently skipped. Bind mounts appear as real directories and are found correctly.

When the host project directory does not yet exist (first run), the entrypoint creates it and falls back to a symlink, which is sufficient until the first session is recorded. On subsequent runs, the bind mount takes over.

The result is that `/resume` works across container runs and across restarts without any manual session management.

## Docker Access

Use the `-DockerAccess` switch to let Claude build images, run containers, or interact with Docker inside the container:

```powershell
dclaude -DockerAccess
```

This mounts the host's Docker socket or named pipe into the container:

| Host OS | Mount |
|---|---|
| Linux / macOS | `/var/run/docker.sock:/var/run/docker.sock:rw` |
| Windows | `//./pipe/docker_engine://./pipe/docker_engine` |

No pre-existence check is performed on the socket or pipe — Docker Desktop resolves paths internally, so host-side checks (e.g., `Test-Path` on the WSL socket path) can give false negatives even when the mount works.

**Security note:** Mounting the Docker socket gives Claude full access to the host's Docker daemon. This effectively grants root-equivalent access to the host — Claude can start privileged containers, mount arbitrary host paths, etc. Only use `-DockerAccess` when you need it and understand the implications.

## Security Model

dclaude's purpose is to move the trust boundary from Claude Code's permission system to the Docker container. Inside the container, Claude runs with `--dangerously-skip-permissions` and has full access to everything mounted. The container limits what "everything" means.

**Compared to running Claude Code directly on the host** (the alternative), dclaude provides a strictly smaller attack surface:

| Concern | Host (no container) | dclaude |
|---------|-------------------|---------|
| Filesystem access | Full host filesystem | Only explicitly mounted paths |
| Environment variables | All host env vars visible | `ANTHROPIC_*`, `CLAUDE_CODE_*`, `CLOUD_ML_*` always forwarded; additional patterns configurable via `envPassthrough` in user/image config |
| Claude config (`~/.claude`) | Full read/write | Mounted read-write (same access, but contained) |
| `.claude.json` sanitization | Host file used as-is | Host paths stripped, workspace pre-accepted |
| Process isolation | None — runs as your user | Docker container boundary |
| Network | Full host network | Docker default network (outbound only) |

### `.claude.json` Sanitization

The host `~/.claude.json` file is not mounted directly into the container. Instead, the entrypoint reads it from a staging path, transforms it, and writes the result to the container's `~/.claude.json`. The transformations applied on every run:

| Field | Action | Reason |
|---|---|---|
| `projects` | Deleted, then re-created with the container workspace path pre-accepted | Host project paths are not valid inside the container; pre-accepting the workspace suppresses the trust dialog |
| `githubRepoPaths` | Deleted | Host-specific paths that are meaningless inside the container |
| `officialMarketplaceAutoInstallAttempted` | Set to `true` | Suppresses the one-time marketplace install prompt |
| `officialMarketplaceAutoInstalled` | Set to `true` | Suppresses the one-time marketplace install prompt |

The host file is never modified. All other settings (themes, model preferences, keybindings, etc.) are preserved.

**Things dclaude does not protect against:**

- **Malicious container images.** If you pull an untrusted image and run it with dclaude, the image has full access to your mounted workspace and Claude config. Build your own images or use trusted sources.
- **Secrets in mounted volumes.** Volumes you configure (via image config or project config) are accessible inside the container. Don't mount directories containing credentials unless you intend Claude to access them.
- **Workspace modifications.** The workspace is mounted read-write by design — Claude needs to edit your code. A misbehaving Claude session can modify any file in the mounted workspace, same as on the host.

The container is not a sandbox against a determined attacker — it is a practical boundary that limits blast radius compared to running Claude Code unrestricted on your host.

## Init Scripts

Init scripts let you customize container startup without modifying base images. Place scripts in `init.d` directories and they run automatically before Claude launches.

### Directory Convention

Scripts are discovered by convention from two locations (user-level and project-level), each with a `common` folder (all images) and an image-specific folder:

| Directory | Scope | Runs for |
|---|---|---|
| `~/.dclaude/common.init.d/` | User | All images |
| `~/.dclaude/<image-name>.init.d/` | User | Named image only |
| `.dclaude/common.init.d/` | Project | All images |
| `.dclaude/<image-name>.init.d/` | Project | Named image only |

Execution order: user common → user image → project common → project image.

### Platform Scripts

The Linux entrypoint sources `*.sh` files; the Windows entrypoint dot-sources `*.ps1` files. To support both platforms, place both variants in the same directory:

```
~/.dclaude/dotnet-core.init.d/
  setup-nuget.sh       # Linux containers
  setup-nuget.ps1      # Windows containers
```

Scripts are sourced (not executed as subprocesses), so environment variable changes persist into the Claude session.

### Example: Adding a NuGet Source

```sh
# ~/.dclaude/dotnet-core.init.d/setup-nuget.sh
dotnet nuget add source "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json" \
  --name myfeed --username az --password "$VSS_NUGET_TOKEN" --store-password-in-clear-text
```

### Known Limitations

- **Shell assumption:** Linux scripts must be `*.sh` (Bash); Windows scripts must be `*.ps1` (PowerShell). There is no shebang-based dispatch.
- **Image name required:** Image-specific init directories (e.g., `dotnet-core.init.d/`) only work when the image is resolved via `-ImageKey` or a project config `imageKey`. When using `-Image` with a direct tag, only `common.init.d/` scripts run.

## Private Files

The `LocalImages/` and `LocalScripts/` directories are gitignored. Use them for private Dockerfiles, build scripts, or any other files you don't want committed to the repository.
