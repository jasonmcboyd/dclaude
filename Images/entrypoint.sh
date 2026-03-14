#!/bin/sh
set -e

HOST_DIR="/mnt/host-claude"
HOST_JSON="/mnt/host-claude.json"
CLAUDE_HOME="/home/claude/.claude"
CLAUDE_JSON="/home/claude/.claude.json"

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
- The workspace at \`/workspace\` is mounted from the host path \`$host_path\`.
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
| \`$host_path\` | \`/workspace\` | read/write |
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

# Link host conversation history so /resume finds conversations from the host.
# The project dir may already be bind-mounted by Invoke-DClaude (preferred, since
# bind mounts appear as real directories to readdir). Fall back to a symlink if not.
project_target="$CLAUDE_HOME/projects/-workspace"
if [ -d "$project_target" ]; then
    # Already bind-mounted by the launcher — nothing to do.
    session_count=$(ls "$project_target"/*.jsonl 2>/dev/null | wc -l)
    echo "[dclaude] Project dir mounted with $session_count session(s)" >&2
elif [ -n "$DCLAUDE_HOST_PATH" ] && [ -d "$HOST_DIR/projects" ]; then
    host_key=$(printf '%s' "$DCLAUDE_HOST_PATH" | sed 's/[/\\:]/-/g')
    host_project_dir="$HOST_DIR/projects/$host_key"
    if [ -d "$host_project_dir" ]; then
        mkdir -p "$CLAUDE_HOME/projects"
        ln -sfn "$host_project_dir" "$project_target"
        session_count=$(ls "$host_project_dir"/*.jsonl 2>/dev/null | wc -l)
        echo "[dclaude] Linked $session_count session(s) from $host_project_dir" >&2
    else
        echo "[dclaude] WARN: host project dir not found: $host_project_dir" >&2
    fi
else
    echo "[dclaude] WARN: no DCLAUDE_HOST_PATH or no host projects dir (DCLAUDE_HOST_PATH='$DCLAUDE_HOST_PATH')" >&2
fi

# Sanitize .claude.json — strip Windows paths that cause junk folders
if [ -f "$HOST_JSON" ]; then
    node -e "
        const fs = require('fs');
        const cfg = JSON.parse(fs.readFileSync('$HOST_JSON', 'utf8'));
        delete cfg.projects;
        delete cfg.githubRepoPaths;
        cfg.officialMarketplaceAutoInstallAttempted = true;
        cfg.officialMarketplaceAutoInstalled = true;
        cfg.projects = { '/workspace': { allowedTools: [], hasTrustDialogAccepted: true } };
        fs.writeFileSync('$CLAUDE_JSON', JSON.stringify(cfg, null, 2));
    "
fi

exec claude --dangerously-skip-permissions "$@"
