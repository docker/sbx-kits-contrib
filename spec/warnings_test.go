package spec

import (
	"testing"
)

func TestRecordDeprecation(t *testing.T) {
	w := &warnings{}
	w.deprecate("memory", "use agentContext instead")
	w.deprecate("kitDir", "field is no longer read")

	if len(w.messages) != 2 {
		t.Fatalf("expected 2 warnings, got %d", len(w.messages))
	}
	if w.messages[0] != "deprecated field \"memory\": use agentContext instead" {
		t.Errorf("warning[0] = %q", w.messages[0])
	}
	if w.messages[1] != "deprecated field \"kitDir\": field is no longer read" {
		t.Errorf("warning[1] = %q", w.messages[1])
	}
}
