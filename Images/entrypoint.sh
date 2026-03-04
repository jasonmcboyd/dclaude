#!/bin/sh
set -e

HOST_DIR="/mnt/host-claude"
HOST_JSON="/mnt/host-claude.json"
CLAUDE_HOME="/home/claude/.claude"
CLAUDE_JSON="/home/claude/.claude.json"

# Selectively link/copy from the host .claude directory.
# Symlink large data dirs (zero-cost, writes persist to host).
# Copy small config files (so we can sanitize without affecting host).
if [ -d "$HOST_DIR" ]; then
    mkdir -p "$CLAUDE_HOME"

    # Symlink directories — writes go straight to host.
    # Skip 'plugins' — host copy has Windows git config that causes junk folders.
    for dir in "$HOST_DIR"/*/; do
        name=$(basename "$dir")
        [ "$name" = "plugins" ] && continue
        ln -sfn "$dir" "$CLAUDE_HOME/$name"
    done

    # Copy top-level files (small config files)
    for file in "$HOST_DIR"/*; do
        [ -f "$file" ] && cp "$file" "$CLAUDE_HOME/$(basename "$file")"
    done
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
        fs.writeFileSync('$CLAUDE_JSON', JSON.stringify(cfg, null, 2));
    "
fi

exec claude --dangerously-skip-permissions "$@"
