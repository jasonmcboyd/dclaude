package initd

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, dir, name string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte("noop"), 0o644); err != nil {
		t.Fatalf("write %s: %v", name, err)
	}
}

func TestRun_OrdersAndFiltersScripts(t *testing.T) {
	dir1 := t.TempDir()
	dir2 := t.TempDir()
	writeFile(t, dir1, "20-b.sh")
	writeFile(t, dir1, "10-a.sh")
	writeFile(t, dir1, "notes.txt") // wrong extension, ignored
	writeFile(t, dir2, "30-c.sh")

	var ran []string
	results := Run([]string{dir1, filepath.Join(dir1, "missing"), dir2}, ".sh", func(p string) error {
		ran = append(ran, filepath.Base(p))
		return nil
	})

	want := []string{"10-a.sh", "20-b.sh", "30-c.sh"}
	if len(ran) != len(want) {
		t.Fatalf("ran %v, want %v", ran, want)
	}
	for i := range want {
		if ran[i] != want[i] {
			t.Fatalf("order wrong: ran %v, want %v", ran, want)
		}
	}
	if len(results) != len(want) {
		t.Fatalf("expected %d results, got %d", len(want), len(results))
	}
}

func TestRun_CapturesPerScriptErrors(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "a.sh")
	boom := errors.New("boom")

	results := Run([]string{dir}, ".sh", func(string) error { return boom })
	if len(results) != 1 || !errors.Is(results[0].Err, boom) {
		t.Fatalf("expected one captured error, got %+v", results)
	}
}
