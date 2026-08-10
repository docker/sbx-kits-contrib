package spec

import "fmt"

// V2View is a loaded Artifact re-expressed in the canonical kit-spec v2
// grammar (spec/SPEC-v2.md): the shape an author writes in a
// `schemaVersion: "2"` spec.yaml.
//
// It exists because the canonical Artifact/Manifest field names are the
// engine's internal vocabulary, and several are not valid v2 YAML keys at
// all — `caps`, `commands.initFiles`, `agentContext`, `template`,
// `resources.memoryMB`, `publishedPorts`. Anything that renders a kit back
// out for a human (or back to disk) therefore needs this mapping, and two
// consumers had grown their own copy of it: scripts/migrate-v1-to-v2.go and
// the engine's `sbx kit inspect --json`. This is the single implementation
// they share.
//
// Scope is deliberately the grammar only — the fields a spec.yaml can
// contain. Load-time output (Artifact.Warnings) and artifact payload
// (Artifact.Files) are not spec keys, so consumers that want to report them
// embed V2View and add their own fields rather than having them appear here.
//
// Both `json` and `yaml` tags are set: the migrator emits YAML, `kit inspect`
// emits JSON, and they must not drift.
//
// Field order is the emit order for YAML (yaml.Marshal writes fields in
// declaration order) and matches the ordering the migrator has always
// produced, so re-emitting an existing kit is byte-stable.
type V2View struct {
	SchemaVersion string `json:"schemaVersion" yaml:"schemaVersion"`
	Kind          string `json:"kind" yaml:"kind"`
	Name          string `json:"name" yaml:"name"`
	Version       string `json:"version,omitempty" yaml:"version,omitempty"`
	DisplayName   string `json:"displayName,omitempty" yaml:"displayName,omitempty"`
	Description   string `json:"description,omitempty" yaml:"description,omitempty"`
	SourceURL     string `json:"sourceURL,omitempty" yaml:"sourceURL,omitempty"`

	Extends  string    `json:"extends,omitempty" yaml:"extends,omitempty"`
	Mixins   []string  `json:"mixins,omitempty" yaml:"mixins,omitempty"`
	Requires *Requires `json:"requires,omitempty" yaml:"requires,omitempty"`
	Locked   []string  `json:"locked,omitempty" yaml:"locked,omitempty"`
	Licenses []string  `json:"licenses,omitempty" yaml:"licenses,omitempty"`

	Args map[string]KitArg `json:"args,omitempty" yaml:"args,omitempty"`

	Sandbox           *V2Sandbox           `json:"sandbox,omitempty" yaml:"sandbox,omitempty"`
	AgentInstructions *V2AgentInstructions `json:"agentInstructions,omitempty" yaml:"agentInstructions,omitempty"`
	Permissions       *V2Permissions       `json:"permissions,omitempty" yaml:"permissions,omitempty"`
	Volumes           []MountSpec          `json:"volumes,omitempty" yaml:"volumes,omitempty"`
	Security          *Security            `json:"security,omitempty" yaml:"security,omitempty"`
	Ports             []PublishedPort      `json:"ports,omitempty" yaml:"ports,omitempty"`
	Credentials       []Credential         `json:"credentials,omitempty" yaml:"credentials,omitempty"`
	Environment       *V2Environment       `json:"environment,omitempty" yaml:"environment,omitempty"`
	Setup             *V2Setup             `json:"setup,omitempty" yaml:"setup,omitempty"`
}

// V2Sandbox is the `sandbox:` block (SPEC-v2 §3.2). Image is the canonical
// Manifest.Template.
type V2Sandbox struct {
	Image      string       `json:"image,omitempty" yaml:"image,omitempty"`
	Build      *BuildConfig `json:"build,omitempty" yaml:"build,omitempty"`
	Entrypoint []string     `json:"entrypoint,omitempty" yaml:"entrypoint,omitempty"`
	Command    *V2Command   `json:"command,omitempty" yaml:"command,omitempty"`
	Resources  *V2Resources `json:"resources,omitempty" yaml:"resources,omitempty"`
}

// V2Command is the structured `sandbox.command` form (SPEC-v2 §3.2.3). The
// list shorthand is never emitted; the structured form is always valid.
type V2Command struct {
	Default     []string `json:"default,omitempty" yaml:"default,omitempty"`
	Interactive []string `json:"interactive,omitempty" yaml:"interactive,omitempty"`
}

// V2Resources mirrors `sandbox.resources` with memory as the byte-size string
// the v2 grammar uses, rather than the internal memoryMB integer.
type V2Resources struct {
	CPU    float64 `json:"cpu,omitempty" yaml:"cpu,omitempty"`
	Memory string  `json:"memory,omitempty" yaml:"memory,omitempty"`
	GPU    string  `json:"gpu,omitempty" yaml:"gpu,omitempty"`
}

// V2AgentInstructions is the `agentInstructions:` block (SPEC-v2 §5.1):
// Filename was Manifest.AIFilename, Content was the top-level agentContext
// (v1 `memory:`).
type V2AgentInstructions struct {
	Filename string `json:"filename,omitempty" yaml:"filename,omitempty"`
	Content  string `json:"content,omitempty" yaml:"content,omitempty"`
}

// V2Permissions is the `permissions:` block (SPEC-v2 §5.2) — the v2 home of
// the internal caps.
type V2Permissions struct {
	Network *V2Network `json:"network,omitempty" yaml:"network,omitempty"`
}

// V2Network is the `permissions.network` egress policy.
type V2Network struct {
	Allow []string `json:"allow,omitempty" yaml:"allow,omitempty"`
	Deny  []string `json:"deny,omitempty" yaml:"deny,omitempty"`
}

// V2Environment is `environment:` (SPEC-v2 §5.5), restricted to the canonical
// variables map. The internal EnvironmentPolicy also carries the removed v1
// proxyManaged list; spelling the shape out here keeps it out of the output
// rather than relying on that field's tags.
type V2Environment struct {
	Variables map[string]string `json:"variables,omitempty" yaml:"variables,omitempty"`
}

// V2Setup is the `setup:` block (SPEC-v2 §5.6) — the v2 home of the internal
// commands, with initFiles spelled files.
type V2Setup struct {
	Install []InstallCommand `json:"install,omitempty" yaml:"install,omitempty"`
	Startup []StartupCommand `json:"startup,omitempty" yaml:"startup,omitempty"`
	Files   []InitFile       `json:"files,omitempty" yaml:"files,omitempty"`
}

// NewV2View projects a normalized Artifact into the v2 grammar. Empty blocks
// are omitted entirely, so the result reads like a spec.yaml an author could
// have written rather than a struct dump with zero values.
//
// SchemaVersion is carried through as-is; a caller that is rewriting a kit to
// v2 (the migrator) sets it to "2" itself, so this stays a faithful
// projection rather than silently claiming a version the input did not have.
//
// The sandbox entrypoint is reconstructed best-effort from
// Manifest.Binary/RunOptions/InteractiveOptions. That recovers the effective
// argv per mode exactly, but not the author's original
// entrypoint-vs-command split: the loader folds a v2 entrypoint tail into
// RunOptions/InteractiveOptions and the split is not retained anywhere. A
// caller with access to the source YAML can restore the true split with
// SetSandboxEntrypoint.
func NewV2View(a *Artifact) *V2View {
	m := &a.Manifest

	v := &V2View{
		SchemaVersion: m.SchemaVersion,
		Kind:          m.Kind,
		Name:          m.Name,
		Version:       m.Version,
		DisplayName:   m.DisplayName,
		Description:   m.Description,
		SourceURL:     m.SourceURL,
		Extends:       a.Extends,
		Mixins:        a.Mixins,
		Requires:      a.Requires,
		Locked:        a.Locked,
		Licenses:      a.Licenses,
		Args:          a.Args,
		Volumes:       m.Volumes,
		Security:      m.Security,
		Ports:         a.PublishedPorts,
		Credentials:   a.Credentials,
	}

	if m.AIFilename != "" || a.AgentContext != "" {
		v.AgentInstructions = &V2AgentInstructions{
			Filename: m.AIFilename,
			Content:  a.AgentContext,
		}
	}

	if a.Caps != nil && a.Caps.Network != nil &&
		(len(a.Caps.Network.Allow) > 0 || len(a.Caps.Network.Deny) > 0) {
		v.Permissions = &V2Permissions{
			Network: &V2Network{Allow: a.Caps.Network.Allow, Deny: a.Caps.Network.Deny},
		}
	}

	if a.Environment != nil && len(a.Environment.Variables) > 0 {
		v.Environment = &V2Environment{Variables: a.Environment.Variables}
	}

	if c := a.Commands; c != nil &&
		(len(c.Install) > 0 || len(c.Startup) > 0 || len(c.InitFiles) > 0) {
		v.Setup = &V2Setup{Install: c.Install, Startup: c.Startup, Files: c.InitFiles}
	}

	hasEntrypoint := m.Binary != "" || len(m.RunOptions) > 0 || len(m.InteractiveOptions) > 0
	if m.Template != "" || m.Build != nil || m.Resources != nil || hasEntrypoint {
		sb := &V2Sandbox{Image: m.Template, Build: m.Build}
		if m.Binary != "" {
			sb.Entrypoint = []string{m.Binary}
		}
		if len(m.RunOptions) > 0 || len(m.InteractiveOptions) > 0 {
			sb.Command = &V2Command{Default: m.RunOptions, Interactive: m.InteractiveOptions}
		}
		if r := m.Resources; r != nil {
			rv := &V2Resources{CPU: r.CPU, GPU: r.GPU}
			if r.MemoryMB > 0 {
				// MemoryMB is whole megabytes; emit the byte-size string the
				// v2 grammar expects (round-trips through units.RAMInBytes).
				rv.Memory = fmt.Sprintf("%dm", r.MemoryMB)
			}
			sb.Resources = rv
		}
		v.Sandbox = sb
	}

	return v
}

// SetSandboxEntrypoint replaces the reconstructed entrypoint/command split
// with an explicit one, for callers that can read the author's original
// split from the source YAML (see NewV2View's note on why it cannot be
// recovered from the canonical model). The sandbox block is created if the
// projection did not produce one.
//
// A command block is emitted only when there is a mode-specific tail, so a
// kit whose entrypoint carries everything stays free of an empty `command:`.
func (v *V2View) SetSandboxEntrypoint(entrypoint, defaultArgs, interactiveArgs []string) {
	if v.Sandbox == nil {
		v.Sandbox = &V2Sandbox{}
	}
	v.Sandbox.Entrypoint = entrypoint
	if len(defaultArgs) > 0 || len(interactiveArgs) > 0 {
		v.Sandbox.Command = &V2Command{Default: defaultArgs, Interactive: interactiveArgs}
		return
	}
	v.Sandbox.Command = nil
}
