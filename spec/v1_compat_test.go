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
