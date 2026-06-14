package bootstrap

import (
	"fmt"
	"io"
	"os"
)

// Logger writes dclaude-prefixed diagnostics to a stream (stderr in production).
//
// There is deliberately no implicit abort: callers decide which failures are fatal by
// choosing Fatalf vs Warnf. This is the structural reason the Go entrypoint cannot
// silently die the way the shell entrypoints could under `set -e` / `$ErrorActionPreference`.
type Logger struct {
	w       io.Writer
	verbose bool
}

// NewLogger returns a Logger writing to w. Verbose output is gated on DCLAUDE_VERBOSE.
func NewLogger(w io.Writer) *Logger {
	return &Logger{w: w, verbose: os.Getenv("DCLAUDE_VERBOSE") != ""}
}

// Infof logs an informational line.
func (l *Logger) Infof(format string, args ...any) {
	_, _ = fmt.Fprintf(l.w, "[dclaude] "+format+"\n", args...)
}

// Warnf logs a non-fatal warning. Best-effort steps use this and continue.
func (l *Logger) Warnf(format string, args ...any) {
	_, _ = fmt.Fprintf(l.w, "[dclaude] WARN: "+format+"\n", args...)
}

// Verbosef logs only when DCLAUDE_VERBOSE is set.
func (l *Logger) Verbosef(format string, args ...any) {
	if l.verbose {
		_, _ = fmt.Fprintf(l.w, "[dclaude] "+format+"\n", args...)
	}
}

// Fatalf logs a fatal error and terminates the process. Reserved for the few steps that
// must succeed (runtime user creation, config parse, the final exec).
func (l *Logger) Fatalf(format string, args ...any) {
	_, _ = fmt.Fprintf(l.w, "[dclaude] FATAL: "+format+"\n", args...)
	osExit(1)
}

// osExit is indirected so tests can intercept termination.
var osExit = os.Exit
