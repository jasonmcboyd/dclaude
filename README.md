# dclaude

Run Claude Code with `--dangerously-skip-permissions` inside Docker containers so the container itself is the security boundary. Your project, Claude config, API key, and configurable volumes are mounted into an isolated container where Claude can operate freely without risk to your host system.

## Prerequisites

- Docker (Windows, macOS, or Linux)
- PowerShell 5.1 or later
- `ANTHROPIC_API_KEY` set in your environment
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

When neither `-Image` nor `-ImageKey` is specified, the image is resolved from the project config file (`.dclaude/settings.json`) in the working directory.

## Configuration

### User Config — `~/.dclaude/settings.json`

Defines named images and their per-platform volume mounts. Lives in your home directory and applies across all projects.

```json
{
  "images": {
    "pwsh": {
      "windows": {
        "tag": "dclaude-pwsh:latest",
        "volumes": ["%USERPROFILE%\\.nuget:C:/Users/ContainerUser/.nuget"]
      },
      "linux": {
        "tag": "dclaude-pwsh-linux:latest"
      }
    },
    "dotnet-core": {
      "windows": {
        "tag": "dclaude-dotnet-core:latest"
      },
      "linux": {
        "tag": "dclaude-dotnet-core-linux:latest",
        "volumes": ["%HOME%/.nuget:/root/.nuget"]
      }
    }
  }
}
```

Each key under `images` is an image name you can pass to `-ImageKey`. The value is an object with one or more platform keys:

| Field | Required | Description |
|---|---|---|
| `images.<name>.windows` | No* | Windows platform configuration. |
| `images.<name>.linux` | No* | Linux platform configuration. |
| `images.<name>.<platform>.tag` | Yes | Docker image tag to run. |
| `images.<name>.<platform>.volumes` | No | Array of volume mounts in `host:container` format. Mounted read-only by default; append `:rw` to make writable. Environment variables are expanded at runtime via .NET's `ExpandEnvironmentVariables`. Use `%VAR%` syntax — this works cross-platform. |

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

## Managing Images

Use `Add-DClaudeImage`, `Get-DClaudeImage`, and `Remove-DClaudeImage` to manage image entries without editing JSON files directly.

```powershell
# Add a Windows image
Add-DClaudeImage -Name dotnet-core -Tag dclaude-dotnet-core:latest -Platform Windows

# Add a Linux variant for the same image
Add-DClaudeImage -Name dotnet-core -Tag dclaude-dotnet-core-linux:latest -Platform Linux

# Add with volume mounts
Add-DClaudeImage -Name dotnet-core -Tag dclaude-dotnet-core:latest -Platform Windows -Volumes '%USERPROFILE%\.nuget:C:/Users/ContainerUser/.nuget'

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

## Building Images

The repository includes Dockerfiles for building images. Use `scripts/Build-Image.ps1` to build them locally. The script auto-detects whether Docker is in Windows or Linux container mode and builds the matching image.

```powershell
# PowerShell — builds Windows or Linux variant depending on Docker mode
./scripts/Build-Image.ps1 -Name pwsh

# .NET SDK — builds Windows (SDK 8.0) or Linux (SDK 10.0) variant
./scripts/Build-Image.ps1 -Name dotnet-core

# .NET Framework SDK 4.8.1 (Windows only)
./scripts/Build-Image.ps1 -Name dotnet-framework
```

Windows images are built from `Images/Dockerfile` and Linux images from `Images/Dockerfile.linux`. Linux images run as a non-root `claude` user (required by Claude Code). The Windows Dockerfile:

- Accepts a `BASE_IMAGE` build argument pointing to any Windows container base
- Installs Git for Windows (required by Claude Code)
- Installs Node.js 22 LTS and `@anthropic-ai/claude-code` globally
- Sets the entrypoint to `claude --dangerously-skip-permissions`
- Trusts the workspace directory as a safe Git directory

These images are provided as a convenience. Any Docker image with Claude Code installed works with dclaude — the module auto-detects the container OS and sets paths accordingly.

To build a custom image from a different base, pass `--build-arg` directly to Docker:

```powershell
docker build --build-arg "BASE_IMAGE=my-base:latest" -t my-custom:latest -f Images/Dockerfile Images/
```

## What Gets Mounted

Every container run by `dclaude` receives these mounts automatically:

| Host path | Container path (Windows) | Container path (Linux) | Mode | Purpose |
|---|---|---|---|---|
| `$Path` (working dir) | `C:/workspace` | `/workspace` | read-write | Project files |
| `~/.claude` | `C:/Users/ContainerUser/.claude` | `/home/claude/.claude` | read-only | Claude settings and history |

Additional volume mounts are layered from two sources: image-level volumes defined in the matching platform block of the user config, and project-level volumes from the `volumes` array in the project config. Both sets are applied together and are **read-only by default**. To make a volume writable, append `:rw` to the mount string (e.g., `"/path/on/host:/path/in/container:rw"`). The `ANTHROPIC_API_KEY` environment variable is forwarded to the container if set on the host. The container OS is auto-detected from `docker info`; the matching platform block is selected and container paths are set accordingly.

## Security Model

dclaude's purpose is to move the trust boundary from Claude Code's permission system to the Docker container. Inside the container, Claude runs with `--dangerously-skip-permissions` and has full access to everything mounted. The container limits what "everything" means.

**Compared to running Claude Code directly on the host** (the alternative), dclaude provides a strictly smaller attack surface:

| Concern | Host (no container) | dclaude |
|---------|-------------------|---------|
| Filesystem access | Full host filesystem | Only explicitly mounted paths |
| Environment variables | All host env vars visible | Only `ANTHROPIC_*`, `CLAUDE_CODE_*`, `CLOUD_ML_*` forwarded |
| Claude config (`~/.claude`) | Full read/write | Mounted read-write (same access, but contained) |
| `.claude.json` sanitization | Host file used as-is | Host paths stripped, workspace pre-accepted |
| Process isolation | None — runs as your user | Docker container boundary |
| Network | Full host network | Docker default network (outbound only) |

**Things dclaude does not protect against:**

- **Malicious container images.** If you pull an untrusted image and run it with dclaude, the image has full access to your mounted workspace and Claude config. Build your own images or use trusted sources.
- **Secrets in mounted volumes.** Volumes you configure (via image config or project config) are accessible inside the container. Don't mount directories containing credentials unless you intend Claude to access them.
- **Workspace modifications.** The workspace is mounted read-write by design — Claude needs to edit your code. A misbehaving Claude session can modify any file in the mounted workspace, same as on the host.

The container is not a sandbox against a determined attacker — it is a practical boundary that limits blast radius compared to running Claude Code unrestricted on your host.

## Private Files

The `LocalImages/` and `LocalScripts/` directories are gitignored. Use them for private Dockerfiles, build scripts, or any other files you don't want committed to the repository.
