package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestV1Memory_MapsToAgentContext(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test-agent
agent:
  image: example/test:latest
memory: |
  Legacy v1 memory content
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}

	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if !strings.Contains(art.AgentContext, "Legacy v1 memory content") {
		t.Errorf("AgentContext not populated from v1 memory: got %q", art.AgentContext)
	}

	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "memory") && strings.Contains(w, "agentContext") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for memory→agentContext, got %v", art.Warnings)
	}
}

func TestV2AgentContext_WinsOverV1Memory(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: agent
name: test-agent
agent:
  image: example/test:latest
memory: "v1 content"
agentContext: "v2 content"
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}

	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if art.AgentContext != "v2 content" {
		t.Errorf("AgentContext = %q; want v2 content (v2 wins on conflict)", art.AgentContext)
	}
}

func TestV1Kind_Agent_MapsToSandbox(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
  image: example/test:latest
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Kind != KindSandbox {
		t.Errorf("Kind = %q; want %q (v1 'agent' normalized to v2 'sandbox')", art.Manifest.Kind, KindSandbox)
	}
	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "kind") && strings.Contains(w, "agent") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for kind: agent, got %v", art.Warnings)
	}
}

func TestV2Kind_Sandbox_Accepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: test
agent:
  image: example/test:latest
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Kind != KindSandbox {
		t.Errorf("Kind = %q; want %q", art.Manifest.Kind, KindSandbox)
	}
	for _, w := range art.Warnings {
		if strings.Contains(w, "kind") {
			t.Errorf("unexpected deprecation warning for v2 kind: %s", w)
		}
	}
}

func TestV1AgentBlock_MapsToSandbox(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
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
	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "agent:") || (strings.Contains(w, "agent") && strings.Contains(w, "sandbox")) {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for agent: block, got %v", art.Warnings)
	}
}

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
	for _, w := range art.Warnings {
		if strings.Contains(w, "agent:") {
			t.Errorf("unexpected deprecation warning for v2 sandbox block: %s", w)
		}
	}
}

func TestVolumesType_TmpfsAccepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: vol-tmpfs
sandbox:
  image: docker/sandbox-templates:shell-docker
volumes:
  - path: /tmp/scratch
    type: tmpfs
    size: 512m
    mode: "1777"
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(art.Manifest.Volumes) != 1 {
		t.Fatalf("expected 1 volume, got %d", len(art.Manifest.Volumes))
	}
	v := art.Manifest.Volumes[0]
	if v.Type != "tmpfs" || v.Path != "/tmp/scratch" || v.Size != "512m" || v.Mode != "1777" {
		t.Errorf("volume mismatch: %#v", v)
	}
}

func TestV1TmpfsBlock_StrictRejected(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: legacy-tmpfs
sandbox:
  image: docker/sandbox-templates:shell-docker
tmpfs:
  - path: /tmp/scratch
    size: 512m
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadFromDirectory(dir)
	if err == nil {
		t.Fatal("expected strict-decode error for removed `tmpfs:` block, got nil")
	}
	if !strings.Contains(err.Error(), "tmpfs") {
		t.Errorf("error should name the rejected field; got %v", err)
	}
}
