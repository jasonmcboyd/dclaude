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
	// installMethod / autoUpdatesProtectedForNative describe how Claude Code was installed
	// on the HOST (e.g. "native" -> ~/.local/bin/claude). Inside the container claude is the
	// npm install in the read-only runtime volume, so carrying these through makes /doctor
	// warn that the native binary is missing. Strip them so claude detects its real location.
	delete(root, "installMethod")
	delete(root, "autoUpdatesProtectedForNative")

	// Suppress the marketplace install prompt.
	root["officialMarketplaceAutoInstallAttempted"] = true
	root["officialMarketplaceAutoInstalled"] = true

	// Re-key the workspace's project entry and force trust acceptance. Claude Code keys its
	// projects map with forward slashes, so a Windows workspace path (C:\...) must be
	// normalized to C:/... or the pre-acceptance won't match and claude re-prompts for trust.
	if entry == nil {
		entry = map[string]any{}
	}
	entry["hasTrustDialogAccepted"] = true
	if _, ok := entry["allowedTools"]; !ok {
		entry["allowedTools"] = []any{}
	}
	root["projects"] = map[string]any{strings.ReplaceAll(workspaceKey, `\`, "/"): entry}

	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("encode .claude.json: %w", err)
	}
	return out, nil
}

// MergeMcpServers merges injected MCP server entries into the project's mcpServers map
// within an already-sanitized .claude.json. Existing server names take precedence over
// injected ones, so user-configured MCP servers are never overwritten.
//
// serversJSON is a JSON object mapping server names to their config objects, e.g.
// `{"sql-mcp":{"url":"http://sql-mcp:3100/mcp"}}`. An empty serversJSON is a no-op.
func MergeMcpServers(sanitized []byte, workspaceKey, serversJSON string) ([]byte, error) {
	if serversJSON == "" {
		return sanitized, nil
	}

	// Decode the servers to inject.
	dec := json.NewDecoder(bytes.NewReader([]byte(serversJSON)))
	dec.UseNumber()
	var servers map[string]any
	if err := dec.Decode(&servers); err != nil {
		return nil, fmt.Errorf("parse MCP inject JSON: %w", err)
	}
	if len(servers) == 0 {
		return sanitized, nil
	}

	// Decode the sanitized config.
	rdec := json.NewDecoder(bytes.NewReader(sanitized))
	rdec.UseNumber()
	var root map[string]any
	if err := rdec.Decode(&root); err != nil {
		return nil, fmt.Errorf("parse sanitized .claude.json: %w", err)
	}

	normalizedKey := strings.ReplaceAll(workspaceKey, `\`, "/")

	projects, ok := root["projects"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("projects map missing in sanitized config")
	}
	entry, ok := projects[normalizedKey].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("project entry %q missing in sanitized config", normalizedKey)
	}

	mcpServers, _ := entry["mcpServers"].(map[string]any)
	if mcpServers == nil {
		mcpServers = map[string]any{}
	}
	for name, cfg := range servers {
		if _, exists := mcpServers[name]; !exists {
			mcpServers[name] = cfg
		}
	}
	entry["mcpServers"] = mcpServers

	out, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("encode .claude.json after MCP merge: %w", err)
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
