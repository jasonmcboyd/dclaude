// Package sanitize implements the single .claude.json transform applied before the
// config enters the container. It replaces the duplicated bash (node -e) and PowerShell
// implementations the shell entrypoints used.
package sanitize

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
)

// Sanitize rewrites a host .claude.json for use inside the container.
//
// Posture: fail-open denylist. Only the known host-specific top-level keys ("projects"
// and "githubRepoPaths") are stripped; every other top-level field passes through
// untouched, so new Claude Code fields are never silently dropped. The host project
// entry that matches hostPath is carried through in full and re-keyed to the container
// workspace with trust force-accepted, so per-project fields (MCP config, session
// pointers, future additions) survive as well.
//
// workspaceKey is the container-side workspace path (the new project key). hostPath is
// the original host workspace path used to locate the source project entry; it may use
// either separator style. A parse error is returned (and is fatal to the caller); valid
// input always yields a workspace project entry with hasTrustDialogAccepted set.
func Sanitize(source []byte, workspaceKey, hostPath string) ([]byte, error) {
	// Decode with UseNumber so integer fields (token counts, timings) round-trip exactly.
	dec := json.NewDecoder(bytes.NewReader(source))
	dec.UseNumber()
	var root map[string]any
	if err := dec.Decode(&root); err != nil {
		return nil, fmt.Errorf("parse .claude.json: %w", err)
	}

	entry := matchingProjectEntry(root["projects"], hostPath)

	// Denylist: strip the known host-specific top-level keys. Everything else stays.
	delete(root, "projects")
	delete(root, "githubRepoPaths")

	// Suppress the marketplace install prompt.
	root["officialMarketplaceAutoInstallAttempted"] = true
	root["officialMarketplaceAutoInstalled"] = true

	// Re-key the workspace's project entry and force trust acceptance.
	if entry == nil {
		entry = map[string]any{}
	}
	entry["hasTrustDialogAccepted"] = true
	if _, ok := entry["allowedTools"]; !ok {
		entry["allowedTools"] = []any{}
	}
	root["projects"] = map[string]any{workspaceKey: entry}

	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("encode .claude.json: %w", err)
	}
	return out, nil
}

// matchingProjectEntry returns the host project entry keyed by hostPath (trying both the
// raw and forward-slash forms), or nil if absent.
func matchingProjectEntry(projects any, hostPath string) map[string]any {
	pm, ok := projects.(map[string]any)
	if !ok || hostPath == "" {
		return nil
	}
	for _, key := range candidateKeys(hostPath) {
		if entry, ok := pm[key].(map[string]any); ok {
			return entry
		}
	}
	return nil
}

// candidateKeys returns the host path and, when different, its forward-slash form. A
// Windows host path (e.g. C:\Users\me) is keyed under either style across Claude Code
// versions, and the binary running in a Linux container still sees a Windows host path.
func candidateKeys(hostPath string) []string {
	slash := strings.ReplaceAll(hostPath, `\`, "/")
	if slash == hostPath {
		return []string{hostPath}
	}
	return []string{hostPath, slash}
}
