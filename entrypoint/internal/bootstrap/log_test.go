package bootstrap

import (
	"bytes"
	"strings"
	"testing"
)

func TestLogger_LevelGating(t *testing.T) {
	t.Run("default: info and warn shown, verbose and debug hidden", func(t *testing.T) {
		t.Setenv("DCLAUDE_VERBOSE", "")
		t.Setenv("DCLAUDE_DEBUG", "")
		var buf bytes.Buffer
		l := NewLogger(&buf)
		l.Infof("info-line")
		l.Warnf("warn-line")
		l.Verbosef("verbose-line")
		l.Debugf("debug-line")

		s := buf.String()
		if !strings.Contains(s, "info-line") {
			t.Error("info should always be shown")
		}
		if !strings.Contains(s, "warn-line") {
			t.Error("warn should always be shown")
		}
		if strings.Contains(s, "verbose-line") {
			t.Error("verbose should be hidden by default")
		}
		if strings.Contains(s, "debug-line") {
			t.Error("debug should be hidden by default")
		}
	})

	t.Run("DCLAUDE_VERBOSE shows verbose but not debug", func(t *testing.T) {
		t.Setenv("DCLAUDE_VERBOSE", "1")
		t.Setenv("DCLAUDE_DEBUG", "")
		var buf bytes.Buffer
		l := NewLogger(&buf)
		l.Verbosef("verbose-line")
		l.Debugf("debug-line")

		s := buf.String()
		if !strings.Contains(s, "verbose-line") {
			t.Error("verbose should be shown when DCLAUDE_VERBOSE is set")
		}
		if strings.Contains(s, "debug-line") {
			t.Error("debug should still be hidden when only DCLAUDE_VERBOSE is set")
		}
	})

	t.Run("DCLAUDE_DEBUG shows debug", func(t *testing.T) {
		t.Setenv("DCLAUDE_VERBOSE", "")
		t.Setenv("DCLAUDE_DEBUG", "1")
		var buf bytes.Buffer
		l := NewLogger(&buf)
		l.Debugf("debug-line")

		if !strings.Contains(buf.String(), "debug-line") {
			t.Error("debug should be shown when DCLAUDE_DEBUG is set")
		}
	})
}
