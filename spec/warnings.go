package spec

import "fmt"

// warnings is a small collector used by the normalize layer to record
// non-fatal validation issues (typically v1 → v2 deprecations). The
// collected messages are surfaced on the loaded Artifact's Warnings slice
// so callers (CLIs, tests) can decide whether to print, ignore, or assert
// on them.
type warnings struct {
	messages []string
}

// deprecate records that a deprecated field was used. note explains
// what to do instead.
func (w *warnings) deprecate(field, note string) {
	w.messages = append(w.messages, fmt.Sprintf("deprecated field %q: %s", field, note))
}
