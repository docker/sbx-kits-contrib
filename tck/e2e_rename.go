package tck

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"

	"go.yaml.in/yaml/v3"
)

// e2eRenameSuffix is appended to a kit name to sidestep a built-in-agent
// name collision for the duration of an e2e run.
const e2eRenameSuffix = "-e2e"

// e2eRenamedKitName returns the name a colliding kit is retried under.
func e2eRenamedKitName(name string) string {
	return name + e2eRenameSuffix
}

// copyKitRenamed copies the kit directory src to dst, with dst's spec.yaml
// (or spec.yml) declaring newName, leaving src untouched.
func copyKitRenamed(src, dst, newName string) error {
	specContent, specName, err := renamedSpec(src, newName)
	if err != nil {
		return err
	}

	root, entries, err := planKitTree(src, specName, specContent, nil)
	if err != nil {
		return fmt.Errorf("copy kit: %w", err)
	}
	if err := os.MkdirAll(dst, 0o700); err != nil {
		return fmt.Errorf("copy kit: %w", err)
	}
	if err := writeStaging(dst, root, entries); err != nil {
		return fmt.Errorf("copy kit: %w", err)
	}

	// The suite loads kits this way too: a parameterized field fails schema
	// validation unless its argument is substituted first.
	if _, err := openKitArtifact(dst); err != nil {
		return fmt.Errorf("copy kit: %q does not load as %q: %w", dst, newName, err)
	}
	return nil
}

// renamedSpec returns src's spec file re-encoded with its top-level name:
// scalar set to newName, plus the name that file was found under.
func renamedSpec(src, newName string) ([]byte, string, error) {
	doc, specName := openSpecDocument(src)
	if doc == nil {
		return nil, "", fmt.Errorf("copy kit: no parseable spec.yaml or spec.yml in %q", src)
	}
	path := filepath.Join(src, specName)

	if len(doc.Content) == 0 || doc.Content[0].Kind != yaml.MappingNode {
		return nil, "", fmt.Errorf("%q: document root is not a mapping", path)
	}

	root := doc.Content[0]
	var nameValue *yaml.Node
	for i := 0; i+1 < len(root.Content); i += 2 {
		if root.Content[i].Kind == yaml.ScalarNode && root.Content[i].Value == "name" {
			nameValue = root.Content[i+1]
			break
		}
	}
	if nameValue == nil {
		return nil, "", fmt.Errorf("%q: no top-level name key", path)
	}
	if nameValue.Kind != yaml.ScalarNode {
		// An alias would take the rewrite silently and still collide.
		return nil, "", fmt.Errorf("%q: name is not a scalar", path)
	}
	nameValue.Value = newName

	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(doc); err != nil {
		return nil, "", fmt.Errorf("encode %q: %w", path, err)
	}
	if err := enc.Close(); err != nil {
		return nil, "", fmt.Errorf("encode %q: %w", path, err)
	}
	return buf.Bytes(), specName, nil
}
