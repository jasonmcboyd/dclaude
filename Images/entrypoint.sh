#!/bin/bash
set -e

# --- Runtime volume PATH setup ---
RUNTIME="${DCLAUDE_RUNTIME:-/opt/dclaude-runtime}"
export PATH="${RUNTIME}/node/bin:${PATH}"

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
mkdir -p /home/claude/.claude

HOST_DIR="/mnt/host-claude"
HOST_JSON="/mnt/host-claude.json"
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
# This runs here instead of the Dockerfile because the workspace path is dynamic.
if command -v git > /dev/null 2>&1; then
    git config --global --add safe.directory "$WORKSPACE"
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

# Selectively link from the host .claude directory.
# Symlink dirs and files so writes (e.g. OAuth token refresh) persist to host.
if [ -d "$HOST_DIR" ]; then
    mkdir -p "$CLAUDE_HOME"

    # Symlink directories — writes go straight to host.
    # Skip 'plugins' — host copy has Windows git config that causes junk folders.
    # Skip 'session-env' — host session environment files reference host paths
    #   and executables that don't exist inside the container. Not skipped on
    #   Windows because Windows containers share the same OS and path structure.
    # Skip 'projects' — handled below to avoid duplicate session entries in /resume.
    # Skip 'rules' — handled below so we can inject a container context file.
    for dir in "$HOST_DIR"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        [ "$name" = "plugins" ] && continue
        [ "$name" = "session-env" ] && continue
        [ "$name" = "projects" ] && continue
        [ "$name" = "rules" ] && continue
        ln -sfn "$dir" "$CLAUDE_HOME/$name"
    done

    # Symlink top-level files so writes (e.g. OAuth token refresh) persist to host.
    for file in "$HOST_DIR"/* "$HOST_DIR"/.*; do
        [ -f "$file" ] && ln -sfn "$file" "$CLAUDE_HOME/$(basename "$file")"
    done
fi

# Create rules directory as a real dir (not symlink) so we can add container
# context without it reaching the host. Symlink individual host rules files in.
container_rules_dir="$CLAUDE_HOME/rules"
mkdir -p "$container_rules_dir"
host_rules_dir="$HOST_DIR/rules"
if [ -d "$host_rules_dir" ]; then
    for file in "$host_rules_dir"/*; do
        [ -f "$file" ] && ln -sfn "$file" "$container_rules_dir/$(basename "$file")"
    done
fi

# Generate container context rules file so Claude knows it's in a container.
host_path="${DCLAUDE_HOST_PATH:-unknown}"
cat > "$container_rules_dir/dclaude-context.md" << CONTEXT_EOF
# Container Environment (dclaude)

You are running inside a dclaude Docker container.

## Key Facts
- The workspace at \`$WORKSPACE\` is mounted from the host path \`$host_path\`.
- Your home directory and .claude config are container-local, with select items symlinked to the host for persistence.
- Paths referenced in CLAUDE.md or other instructions (e.g., project directories, repo paths) may refer to host-only locations that are not mounted in this container.

## When a Path Does Not Exist

If a path mentioned in instructions or config does not exist in the container:

1. Do NOT search for it or attempt workarounds.
2. Inform the user that the path is not available because it was not mounted into the container.
3. Suggest they add a volume mount in their dclaude project or image configuration if they need access.

## Available Mounts

| Host Path | Container Path | Mode |
| --- | --- | --- |
| \`$host_path\` | \`$WORKSPACE\` | read/write |
CONTEXT_EOF

# Append additional volume mounts to the context file
if [ -n "$DCLAUDE_VOLUMES" ]; then
    printf '%s\n' "$DCLAUDE_VOLUMES" | tr '|' '\n' | while IFS= read -r vol; do
        [ -z "$vol" ] && continue
        # Parse volume spec: host:container[:mode]
        # Check if the last segment is a mode flag (ro or rw)
        vol_mode=$(printf '%s' "$vol" | grep -o ':\(ro\|rw\)$' | tr -d ':')
        if [ -n "$vol_mode" ]; then
            # Strip the mode suffix, then split remaining into host:container
            vol_no_mode=$(printf '%s' "$vol" | sed 's/:\(ro\|rw\)$//')
        else
            vol_no_mode="$vol"
        fi
        # Split on the last colon to get host and container
        vol_host=$(printf '%s' "$vol_no_mode" | sed 's/:\([^:]*\)$//')
        vol_container=$(printf '%s' "$vol_no_mode" | sed 's/.*:\([^:]*\)$/\1/')
        if [ "$vol_mode" = "rw" ]; then
            mode_label="read/write"
        else
            mode_label="read-only"
        fi
        printf '| `%s` | `%s` | %s |\n' "$vol_host" "$vol_container" "$mode_label" >> "$container_rules_dir/dclaude-context.md"
    done
fi

# Append Docker access context if the socket is mounted
if [ -S /var/run/docker.sock ]; then
    cat >> "$container_rules_dir/dclaude-context.md" << 'DOCKER_EOF'

## Docker Access

The Docker socket is mounted into this container. You have access to the `docker` CLI and can build images, run containers, and manage Docker resources on the host. The containers you launch are **sibling containers** (not nested) — they run alongside this container on the same Docker daemon.
DOCKER_EOF
fi

# Link host conversation history so /resume finds conversations from the host.
# The project dir may already be bind-mounted by Invoke-DClaude (preferred, since
# bind mounts appear as real directories to readdir). Fall back to a symlink if not.
container_key=$(printf '%s' "$WORKSPACE" | sed 's/[/\\:]/-/g')
project_target="$CLAUDE_HOME/projects/$container_key"
if [ -d "$project_target" ]; then
    # Already bind-mounted by the launcher — nothing to do.
    session_count=$(find "$project_target" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l)
    echo "[dclaude] Project dir mounted with $session_count session(s)" >&2
elif [ -n "$DCLAUDE_HOST_PATH" ] && [ -d "$HOST_DIR/projects" ]; then
    host_key=$(printf '%s' "$DCLAUDE_HOST_PATH" | sed 's/[/\\:]/-/g')
    host_project_dir="$HOST_DIR/projects/$host_key"
    if [ ! -d "$host_project_dir" ]; then
        mkdir -p "$host_project_dir"
    fi
    mkdir -p "$CLAUDE_HOME/projects"
    ln -sfn "$host_project_dir" "$project_target"
    session_count=$(find "$host_project_dir" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l)
    echo "[dclaude] Linked $session_count session(s) from $host_project_dir" >&2
else
    echo "[dclaude] WARN: no DCLAUDE_HOST_PATH or no host projects dir (DCLAUDE_HOST_PATH='$DCLAUDE_HOST_PATH')" >&2
fi

# Sanitize .claude.json — strip Windows paths that cause junk folders
if [ -f "$HOST_JSON" ]; then
    if ! node -e "
        const fs = require('fs');
        const [hostJson, claudeJson, workspace] = process.argv.slice(1);
        const cfg = JSON.parse(fs.readFileSync(hostJson, 'utf8'));
        delete cfg.projects;
        delete cfg.githubRepoPaths;
        cfg.officialMarketplaceAutoInstallAttempted = true;
        cfg.officialMarketplaceAutoInstalled = true;
        cfg.projects = { [workspace]: { allowedTools: [], hasTrustDialogAccepted: true } };
        fs.writeFileSync(claudeJson, JSON.stringify(cfg, null, 2));
    " "$HOST_JSON" "$CLAUDE_JSON" "$WORKSPACE"; then
        echo "[dclaude] FATAL: Failed to sanitize .claude.json" >&2
        exit 1
    fi
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

    # Fix ownership of home dir (entrypoint ran as root, may have created files as root)
    chown -Rh claude:claude /home/claude

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
