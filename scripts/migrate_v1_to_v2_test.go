package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestMigrateSpec_FullShape exercises a v1 spec.yaml that uses every v1 → v2
// transform at once and confirms the output matches the v2-expected golden
// file byte-for-byte, and that every expected deprecation change is reported.
func TestMigrateSpec_FullShape(t *testing.T) {
	input, err := os.ReadFile(filepath.Join("testdata", "v1-full", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}
	expected, err := os.ReadFile(filepath.Join("testdata", "v2-expected", "spec.yaml"))
	if err != nil {
		t.Fatalf("read expected: %v", err)
	}

	got, changes, err := migrateSpec(input)
	if err != nil {
		t.Fatalf("migrateSpec: %v", err)
	}

	if string(got) != string(expected) {
		t.Errorf("output mismatch.\nGOT:\n%s\n\nEXPECTED:\n%s", got, expected)
	}

	// Each v1 surface in the fixture must surface a change line. We assert on
	// substrings (the canonical field name) rather than exact warning strings
	// so wording tweaks in spec/normalize.go don't brittly break this test.
	wantSubstrings := []string{
		"kind: agent",
		"agent:",
		"credentials.sources",
		"network.serviceAuth",
		"network.serviceDomains",
		"environment.proxyManaged",
		"oauth: (standalone block)",
		"network.allowedDomains",
		"network.deniedDomains",
		"network.publishedPorts",
		"memory",
		"settings",
	}
	for _, want := range wantSubstrings {
		found := false
		for _, c := range changes {
			if strings.Contains(c, want) {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("expected a change mentioning %q; got %v", want, changes)
		}
	}
}

// TestMigrateSpec_AlreadyV2 confirms running the migration on a clean v2 spec
// is a no-op: no changes reported.
func TestMigrateSpec_AlreadyV2(t *testing.T) {
	input, err := os.ReadFile(filepath.Join("testdata", "v2-clean", "spec.yaml"))
	if err != nil {
		t.Fatalf("read input: %v", err)
	}

	_, changes, err := migrateSpec(input)
	if err != nil {
		t.Fatalf("migrateSpec: %v", err)
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

	// Summary output mentions a representative sample of the transforms.
	for _, want := range []string{"kind: agent", "agent:", "credentials.sources", "memory", "settings"} {
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

// TestMigrate_Idempotent confirms that migrating an already-migrated spec is a
// no-op: feeding the v2-expected golden back through migrateSpec yields no
// changes. This guards against the migrator churning canonical v2 output.
func TestMigrate_Idempotent(t *testing.T) {
	expected, err := os.ReadFile(filepath.Join("testdata", "v2-expected", "spec.yaml"))
	if err != nil {
		t.Fatalf("read expected: %v", err)
	}

	_, changes, err := migrateSpec(expected)
	if err != nil {
		t.Fatalf("migrateSpec on v2-expected: %v", err)
	}
	if len(changes) != 0 {
		t.Errorf("re-migrating canonical v2 output should be a no-op; got changes %v", changes)
	}
}

// TestMigrateEmitsProxyManaged confirms a v1 environment.proxyManaged entry
// folds onto credentials[].apiKey.proxyManaged: true in the migrated output.
func TestMigrateEmitsProxyManaged(t *testing.T) {
	v1 := []byte(`schemaVersion: "1"
kind: agent
name: t
agent: {image: x}
network:
  serviceDomains: {api.openai.com: openai}
  serviceAuth: {openai: {headerName: Authorization, valueFormat: "Bearer %s"}}
credentials: {sources: {openai: {env: [OPENAI_API_KEY]}}}
environment: {proxyManaged: [OPENAI_API_KEY]}
`)
	out, changes, err := migrateSpec(v1)
	if err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if len(changes) == 0 {
		t.Fatalf("expected migration changes")
	}
	if !strings.Contains(string(out), "proxyManaged: true") {
		t.Fatalf("migrated output missing 'proxyManaged: true':\n%s", out)
	}
}

// TestMigratePreservesRequires confirms a mixin's requires: agent: (base-agent
// affinity) survives the round-trip. The migrator loads the source through the
// spec package and re-emits it, so a missing Requires field in the emit shape
// silently drops affinity — producing a mixin that can be applied to the wrong
// base agent. The network: block forces a re-emit (affinity alone is not a v1
// construct, so it would not trigger migration on its own).
func TestMigratePreservesRequires(t *testing.T) {
	v1 := []byte(`schemaVersion: "1"
kind: mixin
name: t
requires:
  agent: claude
network:
  serviceDomains: {api.openai.com: openai}
  serviceAuth: {openai: {headerName: Authorization, valueFormat: "Bearer %s"}}
credentials: {sources: {openai: {env: [OPENAI_API_KEY]}}}
`)
	out, changes, err := migrateSpec(v1)
	if err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if len(changes) == 0 {
		t.Fatalf("expected migration changes")
	}
	if !strings.Contains(string(out), "requires:") || !strings.Contains(string(out), "agent: claude") {
		t.Fatalf("migrated output dropped 'requires.agent: claude':\n%s", out)
	}
}
