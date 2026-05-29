package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestApplyPhase1Transforms_FullShape exercises a v1 spec.yaml that uses
// every Phase 1 renamed field at once and confirms the output matches
// the v2-expected golden file byte-for-byte. Comments, blank lines, and
// block-scalar formatting must survive.
func TestApplyPhase1Transforms_FullShape(t *testing.T) {
	input, err := os.ReadFile(filepath.Join("testdata", "v1-full", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}
	expected, err := os.ReadFile(filepath.Join("testdata", "v2-expected", "spec.yaml"))
	if err != nil {
		t.Fatalf("read expected: %v", err)
	}

	got, changes := applyPhase1Transforms(string(input))

	if got != string(expected) {
		t.Errorf("output mismatch.\nGOT:\n%s\n\nEXPECTED:\n%s", got, expected)
	}

	wantChanges := []string{
		"kind: agent → kind: sandbox",
		"agent: block → sandbox: block",
		"memory: → agentContext:",
	}
	if len(changes) != len(wantChanges) {
		t.Fatalf("changes len = %d; want %d (got %v)", len(changes), len(wantChanges), changes)
	}
	for i, w := range wantChanges {
		if changes[i] != w {
			t.Errorf("changes[%d] = %q; want %q", i, changes[i], w)
		}
	}
}

// TestApplyPhase1Transforms_AlreadyV2 confirms running the migration on
// a clean v2 spec is a no-op: no transforms applied, no changes
// reported, file content unchanged.
func TestApplyPhase1Transforms_AlreadyV2(t *testing.T) {
	input, err := os.ReadFile(filepath.Join("testdata", "v2-clean", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}

	got, changes := applyPhase1Transforms(string(input))

	if got != string(input) {
		t.Errorf("clean v2 spec should be unchanged.\nGOT:\n%s\n\nORIGINAL:\n%s", got, input)
	}
	if len(changes) != 0 {
		t.Errorf("expected no changes on clean v2 spec, got %v", changes)
	}
}

// TestMigrate_EndToEnd_FullShape exercises the migrate() function on a
// temp-dir copy of the v1 fixture and checks both the rewritten spec
// and the .bak.
func TestMigrate_EndToEnd_FullShape(t *testing.T) {
	dir := t.TempDir()
	original, err := os.ReadFile(filepath.Join("testdata", "v1-full", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}
	specPath := filepath.Join(dir, "spec.yaml")
	if err := os.WriteFile(specPath, original, 0o644); err != nil {
		t.Fatalf("write input: %v", err)
	}

	var out bytes.Buffer
	if err := migrate(dir, &out); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	// Migrated spec.yaml matches the v2-expected fixture.
	expected, err := os.ReadFile(filepath.Join("testdata", "v2-expected", "spec.yaml"))
	if err != nil {
		t.Fatalf("read expected: %v", err)
	}
	got, err := os.ReadFile(specPath)
	if err != nil {
		t.Fatalf("read migrated: %v", err)
	}
	if string(got) != string(expected) {
		t.Errorf("migrated spec.yaml mismatch.\nGOT:\n%s\n\nEXPECTED:\n%s", got, expected)
	}

	// .bak holds the unmodified original.
	bak, err := os.ReadFile(specPath + ".bak")
	if err != nil {
		t.Fatalf("read .bak: %v", err)
	}
	if string(bak) != string(original) {
		t.Errorf(".bak should hold the original; got differing content")
	}

	// Summary output mentions each transform.
	for _, want := range []string{"kind: agent", "agent: block", "memory:"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("summary output missing %q; got: %s", want, out.String())
		}
	}
}

// TestMigrate_EndToEnd_NoChanges exercises a clean v2 spec: the script
// reports no-changes and does NOT create a .bak file (no migration
// happened, nothing to back up).
func TestMigrate_EndToEnd_NoChanges(t *testing.T) {
	dir := t.TempDir()
	original, err := os.ReadFile(filepath.Join("testdata", "v2-clean", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}
	specPath := filepath.Join(dir, "spec.yaml")
	if err := os.WriteFile(specPath, original, 0o644); err != nil {
		t.Fatalf("write input: %v", err)
	}

	var out bytes.Buffer
	if err := migrate(dir, &out); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	if !strings.Contains(out.String(), "no changes needed") {
		t.Errorf("summary should say no changes needed; got: %s", out.String())
	}

	// Spec file is untouched.
	got, err := os.ReadFile(specPath)
	if err != nil {
		t.Fatalf("read spec: %v", err)
	}
	if string(got) != string(original) {
		t.Errorf("clean v2 spec was modified by migration")
	}

	// No .bak created.
	if _, err := os.Stat(specPath + ".bak"); err == nil {
		t.Errorf("unexpected .bak file created for no-op migration")
	}
}

// TestMigrate_MissingSpec returns a clear error when no spec.yaml exists.
func TestMigrate_MissingSpec(t *testing.T) {
	dir := t.TempDir()
	var out bytes.Buffer
	err := migrate(dir, &out)
	if err == nil {
		t.Fatal("expected error for missing spec.yaml; got nil")
	}
	if !strings.Contains(err.Error(), "spec.yaml") {
		t.Errorf("error should mention spec.yaml; got: %v", err)
	}
}

// TestMigrate_RefusesToClobberBackup ensures the script doesn't blow
// away an existing .bak file if the migration is re-run on a directory
// that's already been migrated once.
func TestMigrate_RefusesToClobberBackup(t *testing.T) {
	dir := t.TempDir()
	original, err := os.ReadFile(filepath.Join("testdata", "v1-full", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}
	specPath := filepath.Join(dir, "spec.yaml")
	if err := os.WriteFile(specPath, original, 0o644); err != nil {
		t.Fatalf("write input: %v", err)
	}
	// Pre-create a .bak; migration should refuse to overwrite.
	if err := os.WriteFile(specPath+".bak", []byte("pretend-this-is-a-real-backup"), 0o644); err != nil {
		t.Fatalf("write .bak: %v", err)
	}

	var out bytes.Buffer
	err = migrate(dir, &out)
	if err == nil {
		t.Fatal("expected refusal to clobber existing .bak; got nil")
	}
	if !strings.Contains(err.Error(), ".bak") {
		t.Errorf("error should mention .bak; got: %v", err)
	}
}
