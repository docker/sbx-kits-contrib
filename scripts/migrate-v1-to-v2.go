// Command migrate-v1-to-v2 walks a kit artifact directory, rewrites its
// spec.yaml from the schemaVersion "1" field shapes to the canonical
// schemaVersion "2" shapes, and writes a `.bak` of the original. It is the
// mechanical companion to the v2 spec-package breaking changes — kit authors
// run it once to convert their kit without hand-editing every renamed,
// relocated, or consolidated field.
//
// Usage:
//
//	go run ./scripts/migrate-v1-to-v2 <path-to-kit-directory>
//
// Approach: rather than re-implement the v1 → v2 field rules as text
// substitutions, this tool loads spec.yaml through the repository's spec
// package — the SAME loader the sbx engine uses — which runs the full
// normalize() pass (kind/agent/memory renames, the credentials/network/oauth
// consolidation, caps.network promotion, publishedPorts promotion) and then
// re-emits the normalized result as a canonical v2 spec.yaml. The spec package
// is therefore the single source of truth: when a new v1 → v2 transform lands
// in spec/normalize.go, this tool picks it up for free. See
// sandboxes/docs/specs/2026-05-27-unified-kit-spec-v2.md for the migration
// roadmap.
//
// What it migrates (everything spec.normalize handles, plus the script-level
// settings: drop below):
//
//	kind: agent                → kind: sandbox
//	agent: (v1 sandbox alias)  → sandbox:
//	sandbox.aiFilename         → agentInstructions.filename
//	memory: / agentContext:    → agentInstructions.content
//	sandbox.entrypoint.run     → sandbox.entrypoint (flat array)
//	sandbox.entrypoint.args    → sandbox.command.default
//	sandbox.entrypoint.ttyArgs → sandbox.command.interactive
//	sandbox.entrypoint.pipeMode→ dropped (no v2 equivalent)
//	sandbox.resources.memoryMB → sandbox.resources.memory (byte-size string)
//	credentials.sources        ┐
//	network.serviceDomains     ├→ unified credentials[] (apiKey.name + .inject)
//	network.serviceAuth        │
//	environment.proxyManaged   ┘
//	oauth: (standalone)        → credentials[].oauth
//	network.allowedDomains     → permissions.network.allow
//	network.deniedDomains      → permissions.network.deny
//	network.publishedPorts     → top-level ports
//	commands: / commands.initFiles → setup: / setup.files
//	settings:                  → dropped (move agent setup to setup.files)
//	schemaVersion: "1"         → schemaVersion: "2"
//
// schemaVersion is bumped to "2" so the migrated kit is a fully-declared v2
// spec (matching the v2 design doc's migration-strategy step 1). Note this is
// also the opt-in to the v2 OCI artifact format at distribution time (see
// spec.SupportedSchemaVersions): a "2" kit is rejected by engines that have not
// yet adopted v2, so run this only when your target engines can read v2.
//
// Unlike the original Phase 1 version, this tool is NOT standalone: it imports
// github.com/docker/sbx-kits-contrib/spec, so run it with `go run` from within
// this module rather than against an arbitrary external checkout.
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/docker/sbx-kits-contrib/spec"
	"go.yaml.in/yaml/v3"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: migrate-v1-to-v2 <kit-directory>")
		os.Exit(2)
	}
	if err := migrate(os.Args[1], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

// migrate runs the in-place migration on the spec.yaml under kitDir.
// All progress messages are written to w; the only error condition is
// a real I/O or contract failure (missing spec.yaml, undecodable spec,
// refuse to clobber an existing .bak, etc.). A spec that already uses only
// canonical v2 fields is a successful no-op: nothing is rewritten and no
// .bak is created.
func migrate(kitDir string, w io.Writer) error {
	specPath, err := findSpec(kitDir)
	if err != nil {
		return err
	}

	original, err := os.ReadFile(specPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", specPath, err)
	}

	migrated, changes, err := migrateSpec(original)
	if err != nil {
		return fmt.Errorf("%s: %w", specPath, err)
	}

	if len(changes) == 0 {
		fmt.Fprintf(w, "no changes needed in %s\n", specPath)
		return nil
	}

	bakPath := specPath + ".bak"
	if _, err := os.Stat(bakPath); err == nil {
		return fmt.Errorf("%s already exists; refusing to clobber an existing backup", bakPath)
	}
	if err := os.WriteFile(bakPath, original, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", bakPath, err)
	}
	if err := os.WriteFile(specPath, migrated, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", specPath, err)
	}

	fmt.Fprintf(w, "migrated %s (backup at %s)\n", specPath, bakPath)
	for _, c := range changes {
		fmt.Fprintf(w, "  - %s\n", c)
	}
	return nil
}

// findSpec returns the path to spec.yaml (or spec.yml) under kitDir,
// or an error if neither exists.
func findSpec(kitDir string) (string, error) {
	for _, name := range []string{"spec.yaml", "spec.yml"} {
		path := filepath.Join(kitDir, name)
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("no spec.yaml or spec.yml found in %s", kitDir)
}

// migrateSpec loads v1 (or already-v2) spec.yaml bytes through the spec
// package's normalize pass and re-emits a canonical v2 spec.yaml. It returns
// the rewritten YAML and a list of human-readable change descriptions (the
// spec package's own deprecation warnings, plus any script-level drops such
// as settings:). changes is empty when the input already uses only canonical
// v2 fields, in which case the returned bytes should be ignored (no rewrite).
func migrateSpec(data []byte) ([]byte, []string, error) {
	a, err := spec.LoadArtifactFromBytes(data)
	if err != nil {
		return nil, nil, err
	}

	// normalizeLegacySettings (in the spec package) now emits the settings:
	// deprecation/lift notice into a.Warnings, so the dead Artifact.Settings
	// detector that used to live here is gone — the notice flows through the
	// warnings fold below. A spec that produced no warnings is already
	// canonical v2: nothing to migrate. Returning before the entrypoint
	// re-read below also means a clean v2 spec (whose entrypoint is the flat
	// array shape, not the v1 run/args/ttyArgs mapping) is never fed to the
	// mapping-shaped raw decoder.
	changes := append([]string(nil), a.Warnings...)
	if len(changes) == 0 {
		return data, nil, nil
	}

	// The spec loader flattens the sandbox entrypoint (run/args/ttyArgs) into
	// Manifest.Binary/RunOptions/InteractiveOptions, so it cannot faithfully
	// reconstruct the source entrypoint block. Re-read the raw v1 entrypoint
	// mapping directly from the source YAML and map it onto the v2 flat
	// entrypoint + command split.
	var raw rawSpec
	if err := yaml.Unmarshal(data, &raw); err != nil {
		return nil, nil, fmt.Errorf("re-read entrypoint: %w", err)
	}
	srcSandbox := raw.Sandbox
	if srcSandbox == nil {
		srcSandbox = raw.Agent
	}

	out := buildV2(a, srcSandbox)

	emitted, err := yaml.Marshal(out)
	if err != nil {
		return nil, nil, fmt.Errorf("emit v2 spec: %w", err)
	}

	// Safety net: the rewritten spec must parse cleanly through the same
	// loader. A decode error here means we produced a malformed spec.yaml —
	// fail loudly rather than overwrite the author's file with garbage.
	if _, err := spec.LoadArtifactFromBytes(emitted); err != nil {
		return nil, nil, fmt.Errorf("migrated spec failed to re-parse: %w", err)
	}

	return emitted, changes, nil
}

// buildV2 assembles the canonical v2 output spec from a normalized Artifact.
// The credentials/network/publishedPorts/kind values come from the normalized
// Artifact (where the v1 → v2 consolidation already happened); the sandbox
// entrypoint comes from srcSandbox (the raw source block) so the v1
// run/args/ttyArgs split can be re-expressed as the v2 entrypoint + command
// grammar. The v1 pipeMode has no v2 equivalent and is dropped.
func buildV2(a *spec.Artifact, srcSandbox *rawSandbox) *outSpec {
	out := &outSpec{
		// Always emit the v2 schema version: a migrated kit is a fully-declared
		// v2 spec. This is reached only when there were v1 constructs to migrate
		// (callers gate on a non-empty change list), so a clean v2 spec is never
		// rewritten just to touch this field.
		SchemaVersion:  "2",
		Kind:           a.Manifest.Kind,
		Name:           a.Manifest.Name,
		Version:        a.Manifest.Version,
		DisplayName:    a.Manifest.DisplayName,
		Description:    a.Manifest.Description,
		SourceURL:      a.Manifest.SourceURL,
		Extends:        a.Extends,
		Requires:       a.Requires,
		Locked:         a.Locked,
		Volumes:        a.Manifest.Volumes,
		Security:       a.Manifest.Security,
		PublishedPorts: a.PublishedPorts,
		Credentials:    a.Credentials,
	}

	// agentInstructions: block — filename (was sandbox.aiFilename) +
	// content (was top-level agentContext / v1 memory).
	if a.Manifest.AIFilename != "" || a.AgentContext != "" {
		out.AgentInstructions = &outAgentInstructions{
			Filename: a.Manifest.AIFilename,
			Content:  a.AgentContext,
		}
	}

	// permissions.network block — allow/deny (was caps.network).
	if a.Caps != nil && a.Caps.Network != nil &&
		(len(a.Caps.Network.Allow) > 0 || len(a.Caps.Network.Deny) > 0) {
		out.Permissions = &outPermissions{
			Network: &outNetwork{Allow: a.Caps.Network.Allow, Deny: a.Caps.Network.Deny},
		}
	}

	// setup: block — install/startup + files (was commands, with initFiles
	// renamed to files).
	if a.Commands != nil &&
		(len(a.Commands.Install) > 0 || len(a.Commands.Startup) > 0 || len(a.Commands.InitFiles) > 0) {
		out.Setup = &outSetup{
			Install: a.Commands.Install,
			Startup: a.Commands.Startup,
			Files:   a.Commands.InitFiles,
		}
	}

	srcEntry := v1Entrypoint(srcSandbox)
	if a.Manifest.Template != "" || a.Manifest.Resources != nil || srcEntry != nil {
		sb := &outSandbox{Image: a.Manifest.Template}
		if srcEntry != nil {
			sb.Entrypoint = srcEntry.Run
			if len(srcEntry.Args) > 0 || len(srcEntry.TtyArgs) > 0 {
				sb.Command = &outCommand{Default: srcEntry.Args, Interactive: srcEntry.TtyArgs}
			}
		}
		if r := a.Manifest.Resources; r != nil {
			or := &outResources{CPU: r.CPU, GPU: r.GPU}
			if r.MemoryMB > 0 {
				// MemoryMB is whole megabytes; emit the byte-size string the
				// v2 grammar expects (round-trips through units.RAMInBytes).
				or.Memory = fmt.Sprintf("%dm", r.MemoryMB)
			}
			sb.Resources = or
		}
		out.Sandbox = sb
	}

	if a.Environment != nil && len(a.Environment.Variables) > 0 {
		out.Environment = &outEnv{Variables: a.Environment.Variables}
	}

	return out
}

// outSpec is the canonical v2 spec.yaml emit shape. Field order here is the
// emit order; yaml.Marshal writes struct fields in declaration order. Folded
// and removed v1 blocks (v1 network:, oauth:, settings:, credentials.sources,
// environment.proxyManaged) deliberately have no field here, so they never
// appear in the output.
type outSpec struct {
	SchemaVersion     string                `yaml:"schemaVersion"`
	Kind              string                `yaml:"kind"`
	Name              string                `yaml:"name"`
	Version           string                `yaml:"version,omitempty"`
	DisplayName       string                `yaml:"displayName,omitempty"`
	Description       string                `yaml:"description,omitempty"`
	SourceURL         string                `yaml:"sourceURL,omitempty"`
	Extends           string                `yaml:"extends,omitempty"`
  Requires          *spec.Requires        `yaml:"requires,omitempty"`
	Locked            []string              `yaml:"locked,omitempty"`
	Sandbox           *outSandbox           `yaml:"sandbox,omitempty"`
	AgentInstructions *outAgentInstructions `yaml:"agentInstructions,omitempty"`
	Permissions       *outPermissions       `yaml:"permissions,omitempty"`
	Volumes           []spec.MountSpec      `yaml:"volumes,omitempty"`
	Security          *spec.Security        `yaml:"security,omitempty"`
	PublishedPorts    []spec.PublishedPort  `yaml:"ports,omitempty"`
	Credentials       []spec.Credential     `yaml:"credentials,omitempty"`
	Environment       *outEnv               `yaml:"environment,omitempty"`
	Setup             *outSetup             `yaml:"setup,omitempty"`
}

// outSandbox is the v2 sandbox: block emit shape. entrypoint is the flat
// process prefix; command carries the detached/interactive arg split.
type outSandbox struct {
	Image      string        `yaml:"image,omitempty"`
	Entrypoint []string      `yaml:"entrypoint,omitempty"`
	Command    *outCommand   `yaml:"command,omitempty"`
	Resources  *outResources `yaml:"resources,omitempty"`
}

// outCommand is the sandbox.command emit shape (always the structured form;
// the migrator does not collapse to the shorthand list).
type outCommand struct {
	Default     []string `yaml:"default,omitempty"`
	Interactive []string `yaml:"interactive,omitempty"`
}

// outResources is the sandbox.resources emit shape with memory as a byte-size
// string.
type outResources struct {
	CPU    float64 `yaml:"cpu,omitempty"`
	Memory string  `yaml:"memory,omitempty"`
	GPU    string  `yaml:"gpu,omitempty"`
}

// outAgentInstructions is the v2 top-level agentInstructions: block emit
// shape. filename is only meaningful for a sandbox kit; for a mixin it is
// empty (mixins carry no AIFilename) so it is omitted.
type outAgentInstructions struct {
	Filename string `yaml:"filename,omitempty"`
	Content  string `yaml:"content,omitempty"`
}

// outPermissions is the v2 permissions: block emit shape; today it wraps only
// the network egress policy.
type outPermissions struct {
	Network *outNetwork `yaml:"network,omitempty"`
}

// outNetwork is the v2 permissions.network block emit shape.
type outNetwork struct {
	Allow []string `yaml:"allow,omitempty"`
	Deny  []string `yaml:"deny,omitempty"`
}

// outSetup is the v2 setup: block emit shape (install/startup + files).
type outSetup struct {
	Install []spec.InstallCommand `yaml:"install,omitempty"`
	Startup []spec.StartupCommand `yaml:"startup,omitempty"`
	Files   []spec.InitFile       `yaml:"files,omitempty"`
}

// outEnv is the environment: block emit shape, restricted to the canonical v2
// variables: map (the removed proxyManaged list has no field and so is never
// emitted).
type outEnv struct {
	Variables map[string]string `yaml:"variables,omitempty"`
}

// rawSpec / rawSandbox capture only the entrypoint node from the source
// spec.yaml, accepting both the v1 `agent:` and v2 `sandbox:` spellings. The
// entrypoint is held as a raw node so the v1 mapping shape (run/args/ttyArgs)
// and the v2 flat-array shape can be told apart at decode time.
type rawSpec struct {
	Sandbox *rawSandbox `yaml:"sandbox,omitempty"`
	Agent   *rawSandbox `yaml:"agent,omitempty"`
}

type rawSandbox struct {
	Entrypoint yaml.Node `yaml:"entrypoint,omitempty"`
}

// rawEntrypoint is the v1 entrypoint mapping shape.
type rawEntrypoint struct {
	Run     []string `yaml:"run,omitempty"`
	Args    []string `yaml:"args,omitempty"`
	TtyArgs []string `yaml:"ttyArgs,omitempty"`
}

// v1Entrypoint extracts the v1 run/args/ttyArgs mapping from a source sandbox
// block. It returns nil when there is no entrypoint or when the entrypoint is
// the v2 flat-array shape (which the migrator would never legitimately see,
// since v2 inputs are no-ops before this point).
func v1Entrypoint(src *rawSandbox) *rawEntrypoint {
	if src == nil || src.Entrypoint.Kind != yaml.MappingNode {
		return nil
	}
	var e rawEntrypoint
	if err := src.Entrypoint.Decode(&e); err != nil {
		return nil
	}
	return &e
}
