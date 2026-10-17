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

// notImplemented records that a forward-looking field was accepted at
// decode time but has no runtime effect yet. Distinct from deprecate: the
// field is a future canonical spelling (declared so kits and the published
// v2 docs can use it), not a legacy one being phased out. note explains the
// current limitation.
func (w *warnings) notImplemented(field, note string) {
	w.messages = append(w.messages, fmt.Sprintf("field %q is accepted but not yet implemented: %s", field, note))
}

// ignored records that a field is valid in the schema but has no effect in
// the current context (e.g. a field only meaningful for another kind). note
// explains why it was dropped.
func (w *warnings) ignored(field, note string) {
	w.messages = append(w.messages, fmt.Sprintf("field %q ignored: %s", field, note))
}
