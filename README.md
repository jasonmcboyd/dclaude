# dclaude

Run Claude Code inside Docker containers. Mounts your project, Claude config, API key, and configurable volumes into an isolated container.

## Prerequisites

- Docker (Windows, macOS, or Linux)
- PowerShell 5.1 or later
- `ANTHROPIC_API_KEY` set in your environment
- Claude config at `~/.claude` (created by running `claude` once on the host)

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

If the current directory contains a `.dclaude/settings.json` project config, you can invoke with no parameters and the image is resolved from that file:

```powershell
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

Defines named images and their per-image volume mounts. Lives in your home directory and applies across all projects.

```json
{
  "images": {
    "pwsh-win": {
      "tag": "dclaude-pwsh:latest",
      "volumes": ["%USERPROFILE%\\.nuget:C:/Users/ContainerUser/.nuget"]
    },
    "node-linux": {
      "tag": "my-node-claude:latest",
      "volumes": ["$HOME/.npm:/root/.npm"]
    }
  }
}
```

Each key under `images` is an image name you can pass to `-ImageKey`. The value is an object with:

| Field | Required | Description |
|---|---|---|
| `tag` | Yes | Docker image tag to run. |
| `volumes` | No | Array of volume mounts in `host:container` format. Environment variables are expanded at runtime via .NET's `ExpandEnvironmentVariables`. Use `%VAR%` syntax — this works cross-platform. |

### Project Config — `.dclaude/settings.json`

Place this file in a project directory to set the default image for that project. Committed to source control so the whole team uses the same image.

```json
{
  "imageKey": "pwsh"
}
```

Or with a direct image tag and project-specific volume mounts:

```json
{
  "image": "my-custom:latest",
  "volumes": ["./data:/workspace/data"]
}
```

Container paths in volume mounts depend on the image's OS — use `C:/workspace/...` for Windows containers or `/workspace/...` for Linux containers.

| Field | Description |
|---|---|
| `image` | Direct Docker image tag. Takes precedence over `imageKey`. |
| `imageKey` | References a key in the user config `images` map. |
| `volumes` | Project-specific volume mounts added alongside any image-level volumes from the user config. |

### Local Overrides — `settings.local.json`

Both the user config (`~/.dclaude/`) and project config (`.dclaude/`) directories support a `settings.local.json` file that overrides values from `settings.json`. Local files are never committed — they let you customize settings per-machine without affecting the shared configuration.

When both files exist in the same directory, properties from `settings.local.json` are shallow-merged on top of `settings.json`. For example, to override the image key in a project:

**`.dclaude/settings.json`** (committed):
```json
{
  "imageKey": "pwsh"
}
```

**`.dclaude/settings.local.json`** (git-ignored):
```json
{
  "imageKey": "dotnet",
  "volumes": ["/extra/data:/workspace/data"]
}
```

The effective config would use `dotnet` as the image key and add the extra volume mount. The `settings.local.json` file is excluded via both the repo `.gitignore` and the global gitignore.

When `dclaude` runs with no parameters, image resolution follows this priority order:

1. `-Image` parameter
2. `-ImageKey` parameter
3. `image` field in project config
4. `imageKey` field in project config (resolved through user config)

## Building Images

The repository includes Dockerfiles for Windows Server Core images. Use `scripts/Build-Image.ps1` to build them locally.

```powershell
# PowerShell (Windows Server Core 2022 + PowerShell LTS)
./scripts/Build-Image.ps1 -Name pwsh

# .NET SDK 8 (Windows Server Core 2022)
./scripts/Build-Image.ps1 -Name dotnet-core

# .NET Framework SDK 4.8.1 (Windows Server Core 2022)
./scripts/Build-Image.ps1 -Name dotnet-framework
```

All images are built from `Images/Dockerfile`, which:

- Accepts a `BASE_IMAGE` build argument pointing to any Windows container base
- Installs Git for Windows (required by Claude Code)
- Installs Node.js 22 LTS and `@anthropic-ai/claude-code` globally
- Sets the entrypoint to `claude --dangerously-skip-permissions`
- Trusts the workspace directory as a safe Git directory

These Windows images are provided as a convenience. Any Docker image with Claude Code installed works with dclaude — the module auto-detects the container OS and sets paths accordingly.

To build a custom image from a different base, pass `--build-arg` directly to Docker:

```powershell
docker build --build-arg "BASE_IMAGE=my-base:latest" -t my-custom:latest -f Images/Dockerfile Images/
```

## What Gets Mounted

Every container run by `dclaude` receives these mounts automatically:

| Host path | Container path (Windows) | Container path (Linux) | Purpose |
|---|---|---|---|
| `$Path` (working dir) | `C:/workspace` | `/workspace` | Project files |
| `~/.claude` | `C:/Users/ContainerUser/.claude` | `/root/.claude` | Claude settings and history |

Additional volume mounts come from the image entry in user config (`images.<key>.volumes`) and the project config (`volumes`), in that order. The `ANTHROPIC_API_KEY` environment variable is forwarded to the container if set on the host. The container OS is auto-detected from `docker info`; container paths are set accordingly.
