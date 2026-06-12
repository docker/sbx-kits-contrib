package zsh

import (
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
)

func TestZshSpec(t *testing.T) {
	artifact, err := spec.LoadFromDirectory(".")
	if err != nil {
		t.Fatalf("Failed to load zsh spec: %v", err)
	}

	if artifact.Manifest.Name != "zsh" {
		t.Errorf("Expected name 'zsh', got %q", artifact.Manifest.Name)
	}

	if artifact.Manifest.Kind != "mixin" {
		t.Errorf("Expected kind 'mixin', got %q", artifact.Manifest.Kind)
	}

	if err := spec.ValidateArtifact(artifact); err != nil {
		t.Errorf("Zsh spec validation failed: %v", err)
	}
}
