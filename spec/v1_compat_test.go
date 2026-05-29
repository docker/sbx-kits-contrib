package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestV1Memory_StrictRejected confirms that the v1 `memory:` field is
// no longer accepted at load. v1 kits get a strict-decode error naming
// the offending field; authors migrate by renaming `memory:` →
// `agentContext:` (and running the migration script in
// sbx-kits-contrib/scripts/migrate-v1-to-v2.go).
func TestV1Memory_StrictRejected(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: legacy-memory
sandbox:
  image: example/test:latest
memory: |
  Legacy v1 memory content
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadFromDirectory(dir)
	if err == nil {
		t.Fatal("expected strict-decode error for removed `memory:` field, got nil")
	}
	if !strings.Contains(err.Error(), "memory") {
		t.Errorf("error should name the rejected field; got %v", err)
	}
}

// TestV1Kind_Agent_StrictRejected confirms that `kind: agent` is no
// longer accepted at load — kit authors must use `kind: sandbox`.
func TestV1Kind_Agent_StrictRejected(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: agent
name: legacy-kind
sandbox:
  image: example/test:latest
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadFromDirectory(dir)
	if err == nil {
		t.Fatal("expected error for `kind: agent`, got nil")
	}
	if !strings.Contains(err.Error(), "kind") {
		t.Errorf("error should name the rejected kind value; got %v", err)
	}
}

// TestV1AgentBlock_StrictRejected confirms that the v1 `agent:` block
// is no longer accepted at load. Kit authors must use `sandbox:`.
func TestV1AgentBlock_StrictRejected(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: legacy-agent
agent:
  image: example/test:latest
  aiFilename: TEST.md
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadFromDirectory(dir)
	if err == nil {
		t.Fatal("expected strict-decode error for removed `agent:` block, got nil")
	}
	if !strings.Contains(err.Error(), "agent") {
		t.Errorf("error should name the rejected field; got %v", err)
	}
}

// TestV2SandboxBlock_Accepted exercises the v2 sandbox block end-to-end.
func TestV2SandboxBlock_Accepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: test
sandbox:
  image: example/test:latest
  aiFilename: TEST.md
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Template != "example/test:latest" {
		t.Errorf("Template = %q; want example/test:latest", art.Manifest.Template)
	}
}

// TestV2_FullShape_Phase1Renames asserts that a v2-spelled spec.yaml
// using every field renamed in Phase 1 (`kind: sandbox`, `sandbox:`
// block, `agentContext:`) decodes correctly into the canonical
// Artifact representation. This is the positive counterpart to the
// three v1 strict-rejection tests above and locks in the full
// post-Phase-1 acceptance contract.
func TestV2_FullShape_Phase1Renames(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: phase1-full-shape
displayName: Phase 1 Full Shape
description: exercises every Phase 1 renamed field at once
sandbox:
  image: example/test:latest
  aiFilename: TEST.md
  entrypoint:
    run: ["test-bin"]
    args: ["--flag"]
agentContext: |
  This is the kit's agent-context content. Renamed from the v1
  memory field; v1 spellings now strict-reject.
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	// Renamed top-level: `kind: sandbox`.
	if art.Manifest.Kind != KindSandbox {
		t.Errorf("Manifest.Kind = %q; want %q", art.Manifest.Kind, KindSandbox)
	}

	// Renamed block: `sandbox:` populates Manifest.Template / Binary / RunOptions / AIFilename.
	if art.Manifest.Template != "example/test:latest" {
		t.Errorf("Manifest.Template = %q; want example/test:latest", art.Manifest.Template)
	}
	if art.Manifest.AIFilename != "TEST.md" {
		t.Errorf("Manifest.AIFilename = %q; want TEST.md", art.Manifest.AIFilename)
	}
	if art.Manifest.Binary != "test-bin" {
		t.Errorf("Manifest.Binary = %q; want test-bin", art.Manifest.Binary)
	}
	wantRunOptions := []string{"--flag"}
	if len(art.Manifest.RunOptions) != len(wantRunOptions) || art.Manifest.RunOptions[0] != wantRunOptions[0] {
		t.Errorf("Manifest.RunOptions = %v; want %v", art.Manifest.RunOptions, wantRunOptions)
	}

	// Renamed field: `agentContext:` populates Artifact.AgentContext.
	if !strings.Contains(art.AgentContext, "Renamed from the v1") {
		t.Errorf("Artifact.AgentContext missing expected content; got %q", art.AgentContext)
	}

	// No deprecation warnings — v2 spelling throughout means clean load.
	for _, w := range art.Warnings {
		if strings.Contains(w, "memory") || strings.Contains(w, "agent:") || strings.Contains(w, "kind: agent") {
			t.Errorf("unexpected deprecation warning on clean v2 load: %s", w)
		}
	}
}
