package brew

import (
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
)

func TestBrewSpec(t *testing.T) {
	artifact, err := spec.LoadFromDirectory(".")
	if err != nil {
		t.Fatalf("Failed to load brew spec: %v", err)
	}

	if artifact.Manifest.Name != "brew" {
		t.Errorf("Expected name 'brew', got %q", artifact.Manifest.Name)
	}

	if artifact.Manifest.Kind != "mixin" {
		t.Errorf("Expected kind 'mixin', got %q", artifact.Manifest.Kind)
	}

	if err := spec.ValidateArtifact(artifact); err != nil {
		t.Errorf("Brew spec validation failed: %v", err)
	}
}
