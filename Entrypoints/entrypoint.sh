#!/bin/bash
set -e

# --- Runtime volume PATH setup ---
RUNTIME="${DCLAUDE_RUNTIME:-/opt/dclaude-runtime}"
export PATH="${RUNTIME}/node/bin:${PATH}"

# Ensure truecolor support for CLI tools (stock images may not set this)
export COLORTERM="${COLORTERM:-truecolor}"

# --- Create claude user if not exists (stock images won't have it) ---
if ! id claude >/dev/null 2>&1; then
    # Remove any existing UID 1000 user first (e.g. 'app' in .NET SDK images)
    existing=$(getent passwd 1000 | cut -d: -f1 2>/dev/null || true)
    if [ -n "$existing" ] && [ "$existing" != "claude" ]; then
        userdel "$existing"
    fi
    useradd -m -u 1000 claude 2>/dev/null || adduser -D -u 1000 claude 2>/dev/null || true
fi

# Ensure home directory exists
mkdir -p /home/claude

CLAUDE_HOME="/home/claude/.claude"
CLAUDE_JSON="/home/claude/.claude.json"

# Workspace path: use host-path mount if provided, fall back to legacy /workspace
WORKSPACE="${DCLAUDE_WORKSPACE:-/workspace}"

# Fall back to runtime volume git if the image doesn't have it
if ! command -v git > /dev/null 2>&1 && [ -x "${RUNTIME}/git/bin/git" ]; then
    export GIT_EXEC_PATH="${RUNTIME}/git/libexec/git-core"
    export PATH="${PATH}:${RUNTIME}/git/bin"
fi

# Trust the workspace directory to avoid "dubious ownership" errors from git.
if command -v git > /dev/null 2>&1; then
    git config -f /home/claude/.gitconfig --add safe.directory "$WORKSPACE"
else
    echo "[dclaude] WARN: git is not available. Some Claude Code features may not work." >&2
fi

# --- Root detection and dynamic UID matching ---
if [ "$(id -u)" = "0" ]; then
    # Match claude user's UID to the workspace file owner (for native Linux hosts).
    # On WSL2, workspace files appear as root-owned (UID 0) due to 9P mount — skip in that case.
    ws_uid=$(stat -c '%u' "$WORKSPACE" 2>/dev/null || echo "1000")
    if [ "$ws_uid" != "0" ] && [ "$ws_uid" != "1000" ]; then
        echo "[dclaude] Matching claude UID to workspace owner ($ws_uid)" >&2
        usermod -u "$ws_uid" claude
    fi
fi

# Sanitize .claude.json — strip Windows paths that cause junk folders,
# but preserve MCP server config from the host project entry.
# Source is inside the direct mount; destination is the runtime config location.
CLAUDE_JSON_SOURCE="${CLAUDE_HOME}/.claude.json"
if [ -f "$CLAUDE_JSON_SOURCE" ]; then
    if ! node -e "
        const fs = require('fs');
        const [sourceJson, claudeJson, workspace, hostPath] = process.argv.slice(1);
        const cfg = JSON.parse(fs.readFileSync(sourceJson, 'utf8'));

        // Look up host project entry to preserve MCP fields.
        const mcpFields = ['mcpServers', 'mcpContextUris', 'enabledMcpjsonServers', 'disabledMcpjsonServers'];
        let preserved = {};
        if (cfg.projects && hostPath) {
            const candidates = [hostPath, hostPath.replace(/\\\\/g, '/')];
            for (const key of candidates) {
                if (cfg.projects[key]) {
                    for (const f of mcpFields) {
                        if (cfg.projects[key][f] !== undefined) {
                            preserved[f] = cfg.projects[key][f];
                        }
                    }
                    break;
                }
            }
        }

        delete cfg.projects;
        delete cfg.githubRepoPaths;
        cfg.officialMarketplaceAutoInstallAttempted = true;
        cfg.officialMarketplaceAutoInstalled = true;
        cfg.projects = { [workspace]: { allowedTools: [], hasTrustDialogAccepted: true, ...preserved } };
        fs.writeFileSync(claudeJson, JSON.stringify(cfg, null, 2));
    " "$CLAUDE_JSON_SOURCE" "$CLAUDE_JSON" "$WORKSPACE" "${DCLAUDE_HOST_PATH:-}"; then
        echo "[dclaude] FATAL: Failed to sanitize .claude.json" >&2
        exit 1
    fi
fi

# Check project session history.
# The project dir may already be bind-mounted by Invoke-DClaude (preferred, since
# bind mounts appear as real directories to readdir). Fall back to the directory
# that already exists in the direct mount.
container_key=$(printf '%s' "$WORKSPACE" | sed 's/[/\\:]/-/g')
project_target="$CLAUDE_HOME/projects/$container_key"
if [ -d "$project_target" ]; then
    session_count=$(find "$project_target" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l)
    echo "[dclaude] Project dir with $session_count session(s)" >&2
else
    echo "[dclaude] WARN: no project dir found for key '$container_key'" >&2
fi

# Run init scripts (user common → user image → project common → project image)
INIT_BASE="/mnt/init.d"
for init_dir in "$INIT_BASE/user-common" "$INIT_BASE/user-image" "$INIT_BASE/project-common" "$INIT_BASE/project-image"; do
    [ -d "$init_dir" ] || continue
    for script in "$init_dir"/*.sh; do
        [ -f "$script" ] || continue
        echo "[dclaude] Running init script: $(basename "$script")" >&2
        . "$script"
    done
done

# Link Docker CLI from the provisioned volume (mounted by -DockerAccess),
# but only if the image doesn't already have docker installed.
if ! command -v docker > /dev/null 2>&1 && [ -x /opt/docker-cli/docker ]; then
    ln -sf /opt/docker-cli/docker /usr/local/bin/docker
    if [ -d /opt/docker-cli/cli-plugins ]; then
        mkdir -p /usr/local/lib/docker/cli-plugins
        for plugin in /opt/docker-cli/cli-plugins/*; do
            [ -f "$plugin" ] && ln -sf "$plugin" /usr/local/lib/docker/cli-plugins/
        done
    fi
fi

# --- Privilege drop (when running as root) or direct exec ---
if [ "$(id -u)" = "0" ]; then
    # If the Docker socket is mounted, add claude to a group matching its GID
    # so the unprivileged user can talk to the Docker daemon.
    if [ -S /var/run/docker.sock ]; then
        sock_gid=$(stat -c '%g' /var/run/docker.sock)
        if ! getent group "$sock_gid" > /dev/null 2>&1; then
            groupadd -g "$sock_gid" docker-host
        fi
        usermod -aG "$sock_gid" claude
        echo "[dclaude] Added claude to docker group (GID $sock_gid)" >&2
    fi

    # Fix ownership of home dir (entrypoint ran as root, may have created files as root).
    # Skip the read-only .claude.json bind mount, which can't be chowned and doesn't need
    # to be. The trailing `|| true` is critical: under `set -e`, a non-zero chown exit (e.g.
    # any other read-only mount) would otherwise abort the entrypoint here — before the
    # exec below — and the container would die silently. Ownership fixup is best-effort.
    find /home/claude -path /home/claude/.claude/.claude.json -prune -o \
        -exec chown -h claude:claude {} + || true

    # Drop to claude user with ambient capabilities for WSL2 file timestamp support
    if command -v setpriv > /dev/null 2>&1; then
        exec setpriv --reuid=claude --regid=claude --init-groups \
            --inh-caps=+fowner,+dac_override \
            --ambient-caps=+fowner,+dac_override \
            --no-new-privs \
            -- env PATH="$PATH" HOME="/home/claude" claude --dangerously-skip-permissions "$@"
    else
        echo "[dclaude] WARN: setpriv not found, falling back to su (no ambient caps)" >&2
        exec su -s /bin/sh claude -c "export PATH='$PATH' HOME='/home/claude'; exec claude --dangerously-skip-permissions$(printf ' %q' "$@")"
    fi
fi

export HOME="/home/claude"
exec claude --dangerously-skip-permissions "$@"
