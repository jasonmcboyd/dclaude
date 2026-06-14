package sanitize

import (
	"encoding/json"
	"testing"
)

func mustParse(t *testing.T, b []byte) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("output is not valid JSON: %v\n%s", err, b)
	}
	return m
}

func projectEntry(t *testing.T, m map[string]any, key string) map[string]any {
	t.Helper()
	projects, ok := m["projects"].(map[string]any)
	if !ok {
		t.Fatalf("projects missing or wrong type: %v", m["projects"])
	}
	if len(projects) != 1 {
		t.Fatalf("projects should have exactly the workspace key, got %d: %v", len(projects), projects)
	}
	entry, ok := projects[key].(map[string]any)
	if !ok {
		t.Fatalf("workspace entry %q missing: %v", key, projects)
	}
	return entry
}

func TestSanitize_StripsHostKeysAndForcesTrust(t *testing.T) {
	src := []byte(`{
		"projects": {"C:\\Users\\me\\proj": {"allowedTools": ["Bash"], "mcpServers": {"x": 1}, "lastSessionId": "abc"}},
		"githubRepoPaths": {"a": "b"},
		"oauthAccount": {"id": "keep-me"},
		"someFutureField": 42
	}`)

	out, err := Sanitize(src, "/c/Users/me/proj", `C:\Users\me\proj`)
	if err != nil {
		t.Fatalf("Sanitize: %v", err)
	}
	m := mustParse(t, out)

	if _, ok := m["githubRepoPaths"]; ok {
		t.Error("githubRepoPaths should be stripped")
	}
	if m["officialMarketplaceAutoInstallAttempted"] != true || m["officialMarketplaceAutoInstalled"] != true {
		t.Error("marketplace flags should both be true")
	}
	// fail-open: unknown top-level fields are preserved.
	if _, ok := m["oauthAccount"]; !ok {
		t.Error("oauthAccount (unknown top-level) should be preserved")
	}
	if m["someFutureField"] != float64(42) {
		t.Errorf("someFutureField should be preserved, got %v", m["someFutureField"])
	}

	entry := projectEntry(t, m, "/c/Users/me/proj")
	if entry["hasTrustDialogAccepted"] != true {
		t.Error("workspace entry should have hasTrustDialogAccepted=true")
	}
	// fail-open within the entry: fields from the matched host entry survive the re-key.
	if entry["lastSessionId"] != "abc" {
		t.Errorf("lastSessionId should be preserved (fail-open), got %v", entry["lastSessionId"])
	}
	if _, ok := entry["mcpServers"]; !ok {
		t.Error("mcpServers should be preserved")
	}
}

func TestSanitize_MatchesForwardSlashHostKey(t *testing.T) {
	// Host entry keyed with forward slashes; hostPath supplied with backslashes.
	src := []byte(`{"projects": {"C:/Users/me/proj": {"mcpServers": {"x": 1}}}}`)
	out, err := Sanitize(src, "/c/Users/me/proj", `C:\Users\me\proj`)
	if err != nil {
		t.Fatalf("Sanitize: %v", err)
	}
	entry := projectEntry(t, mustParse(t, out), "/c/Users/me/proj")
	if _, ok := entry["mcpServers"]; !ok {
		t.Error("mcpServers should be preserved when matching the forward-slash host key")
	}
}

func TestSanitize_NoProjectsStillPreAcceptsWorkspace(t *testing.T) {
	src := []byte(`{"hasCompletedOnboarding": true}`)
	out, err := Sanitize(src, "/workspace", "")
	if err != nil {
		t.Fatalf("Sanitize: %v", err)
	}
	m := mustParse(t, out)
	if m["hasCompletedOnboarding"] != true {
		t.Error("unrelated top-level field should be preserved")
	}
	entry := projectEntry(t, m, "/workspace")
	if entry["hasTrustDialogAccepted"] != true {
		t.Error("workspace should be pre-accepted even with no source projects")
	}
}

func TestSanitize_ParseErrorIsReturned(t *testing.T) {
	if _, err := Sanitize([]byte(`{not json`), "/workspace", ""); err == nil {
		t.Fatal("expected a parse error for corrupt JSON")
	}
}
