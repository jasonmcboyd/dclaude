// Package initd discovers and runs dclaude init scripts in a deterministic order.
package initd

import (
	"os"
	"path/filepath"
	"sort"
)

// Result is the outcome of running one init script.
type Result struct {
	Script string
	Err    error
}

// Run discovers scripts with the given extension in each directory (directories in the
// supplied order, scripts sorted by name within a directory) and executes each via
// runner. A missing directory is skipped silently. It returns one Result per script run,
// so the caller can report per-script failures without aborting the whole sequence.
func Run(dirs []string, ext string, runner func(path string) error) []Result {
	var results []Result
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue // a missing init.d directory is normal
		}
		var scripts []string
		for _, e := range entries {
			if e.IsDir() || filepath.Ext(e.Name()) != ext {
				continue
			}
			scripts = append(scripts, filepath.Join(dir, e.Name()))
		}
		sort.Strings(scripts)
		for _, s := range scripts {
			results = append(results, Result{Script: s, Err: runner(s)})
		}
	}
	return results
}
