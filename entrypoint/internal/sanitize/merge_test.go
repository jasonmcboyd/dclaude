package sanitize

import (
	"encoding/json"
	"testing"
)

func TestMergeMcpServers_IntoEmptyMcpServers(t *testing.T) {
	src := []byte(`{
		"projects": {"/workspace": {"hasTrustDialogAccepted": true, "mcpServers": {}}}
	}`)
	out, err := MergeMcpServers(src, "/workspace", `{"sql-mcp":{"url":"http://sql-mcp:3100/mcp"}}`)
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	entry := projectEntry(t, mustParse(t, out), "/workspace")
	servers, ok := entry["mcpServers"].(map[string]any)
	if !ok {
		t.Fatal("mcpServers missing after merge")
	}
	if _, ok := servers["sql-mcp"]; !ok {
		t.Error("sql-mcp should have been injected")
	}
}

func TestMergeMcpServers_IntoExistingNoCollision(t *testing.T) {
	src := []byte(`{
		"projects": {"/workspace": {"mcpServers": {"existing":{"url":"http://existing:8080"}}}}
	}`)
	out, err := MergeMcpServers(src, "/workspace", `{"sql-mcp":{"url":"http://sql-mcp:3100/mcp"}}`)
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	servers := projectEntry(t, mustParse(t, out), "/workspace")["mcpServers"].(map[string]any)
	if _, ok := servers["existing"]; !ok {
		t.Error("existing server should be preserved")
	}
	if _, ok := servers["sql-mcp"]; !ok {
		t.Error("sql-mcp should have been injected")
	}
}

func TestMergeMcpServers_ExistingNameTakesPrecedence(t *testing.T) {
	src := []byte(`{
		"projects": {"/workspace": {"mcpServers": {"sql-mcp":{"url":"http://user-configured:9999"}}}}
	}`)
	out, err := MergeMcpServers(src, "/workspace", `{"sql-mcp":{"url":"http://sidecar:3100/mcp"}}`)
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	servers := projectEntry(t, mustParse(t, out), "/workspace")["mcpServers"].(map[string]any)
	cfg, ok := servers["sql-mcp"].(map[string]any)
	if !ok {
		t.Fatal("sql-mcp entry missing")
	}
	if cfg["url"] != "http://user-configured:9999" {
		t.Errorf("existing user config should take precedence, got url=%v", cfg["url"])
	}
}

func TestMergeMcpServers_NoMcpServersFieldYet(t *testing.T) {
	src := []byte(`{
		"projects": {"/workspace": {"hasTrustDialogAccepted": true}}
	}`)
	out, err := MergeMcpServers(src, "/workspace", `{"sql-mcp":{"url":"http://sql-mcp:3100/mcp"}}`)
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	servers, ok := projectEntry(t, mustParse(t, out), "/workspace")["mcpServers"].(map[string]any)
	if !ok {
		t.Fatal("mcpServers should have been created")
	}
	if _, ok := servers["sql-mcp"]; !ok {
		t.Error("sql-mcp should have been injected")
	}
}

func TestMergeMcpServers_EmptyServersJSONIsNoop(t *testing.T) {
	src := []byte(`{"projects": {"/workspace": {"hasTrustDialogAccepted": true}}}`)
	out, err := MergeMcpServers(src, "/workspace", "")
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	if string(out) != string(src) {
		t.Error("empty serversJSON should return input unchanged")
	}
}

func TestMergeMcpServers_InvalidServersJSONReturnsError(t *testing.T) {
	src := []byte(`{"projects": {"/workspace": {}}}`)
	if _, err := MergeMcpServers(src, "/workspace", `{not json`); err == nil {
		t.Fatal("expected an error for invalid serversJSON")
	}
}

func TestMergeMcpServers_NormalizesWorkspaceKey(t *testing.T) {
	src := []byte(`{
		"projects": {"C:/Users/me/proj": {"hasTrustDialogAccepted": true}}
	}`)
	out, err := MergeMcpServers(src, `C:\Users\me\proj`, `{"sql-mcp":{"url":"http://sql-mcp:3100/mcp"}}`)
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	entry := projectEntry(t, mustParse(t, out), "C:/Users/me/proj")
	servers, ok := entry["mcpServers"].(map[string]any)
	if !ok {
		t.Fatal("mcpServers should have been created")
	}
	if _, ok := servers["sql-mcp"]; !ok {
		t.Error("sql-mcp should have been injected after key normalization")
	}
}

func TestMergeMcpServers_PreservesNumericFields(t *testing.T) {
	src := []byte(`{
		"projects": {"/workspace": {"mcpServers": {}}},
		"tokenCount": 12345
	}`)
	out, err := MergeMcpServers(src, "/workspace", `{"sql-mcp":{"url":"http://sql-mcp:3100/mcp","timeout":30}}`)
	if err != nil {
		t.Fatalf("MergeMcpServers: %v", err)
	}
	m := mustParse(t, out)
	// json.Unmarshal (used by mustParse) decodes numbers as float64, but the encoder used
	// json.Number internally. Verify the value round-trips correctly.
	tc, err := json.Number("12345").Int64()
	if err != nil {
		t.Fatalf("unexpected number parse error: %v", err)
	}
	if int64(m["tokenCount"].(float64)) != tc {
		t.Errorf("numeric field should round-trip, got %v", m["tokenCount"])
	}
}
