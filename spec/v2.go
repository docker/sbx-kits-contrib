package spec

import (
	"bytes"
	"fmt"
	"sort"

	"github.com/docker/go-units"
	"go.yaml.in/yaml/v3"
)

// specFileV2 is the on-disk YAML schema for schemaVersion "2" specs. The
// loader forks on schemaVersion (see peekSchemaVersion), so v1 and v2 never
// share a decode struct: v2 is a clean grammar with no legacy shims, and
// normalizeV2 maps it onto the SAME canonical Artifact the v1 path produces.
// That is why every runtime consumer (and the credential-binding regime keyed
// on Manifest.SchemaVersion) is unaffected by the grammar change.
type specFileV2 struct {
	SchemaVersion string    `yaml:"schemaVersion"`
	Kind          string    `yaml:"kind"`
	Name          string    `yaml:"name"`
	Version       string    `yaml:"version,omitempty"`
	DisplayName   string    `yaml:"displayName,omitempty"`
	Description   string    `yaml:"description,omitempty"`
	SourceURL     string    `yaml:"sourceURL,omitempty"`
	Security      *Security `yaml:"security,omitempty"`

	Extends  string    `yaml:"extends,omitempty"`
	Mixins   []string  `yaml:"mixins,omitempty"`
	Requires *Requires `yaml:"requires,omitempty"`
	Locked   []string  `yaml:"locked,omitempty"`
	Licenses []string  `yaml:"licenses,omitempty"`

	Sandbox           *sandboxBlockV2           `yaml:"sandbox,omitempty"`
	AgentInstructions *agentInstructionsBlockV2 `yaml:"agentInstructions,omitempty"`

	Permissions    *permissionsBlockV2 `yaml:"permissions,omitempty"`
	PublishedPorts []PublishedPort     `yaml:"ports,omitempty"`
	Credentials    []Credential        `yaml:"credentials,omitempty"`
	Environment    *EnvironmentPolicy  `yaml:"environment,omitempty"`
	Volumes        []MountSpec         `yaml:"volumes,omitempty"`
	Setup          *setupBlockV2       `yaml:"setup,omitempty"`
}

// sandboxBlockV2 groups the container-launch configuration. Entrypoint is the
// fixed process prefix (binary + always-on args); Command carries the
// mode-specific tail (detached vs interactive). Resources.Memory is a
// byte-size string (e.g. "4096m", "4g").
type sandboxBlockV2 struct {
	Image      string         `yaml:"image,omitempty"`
	Build      *BuildConfig   `yaml:"build,omitempty"`
	Entrypoint []string       `yaml:"entrypoint,omitempty"`
	Command    commandFieldV2 `yaml:"command,omitempty"`
	Resources  *resourcesV2   `yaml:"resources,omitempty"`
}

// agentInstructionsBlockV2 groups the agent-instruction fields. Filename is the
// AI profile filename (canonical Manifest.AIFilename) and is only meaningful
// for a sandbox kit (an "agent"); it is ignored for a mixin, which cannot own
// the profile filename. Content is the markdown appended to the AI profile
// (canonical Artifact.AgentContext) and applies to both kinds.
type agentInstructionsBlockV2 struct {
	Filename string `yaml:"filename,omitempty"`
	Content  string `yaml:"content,omitempty"`
}

// permissionsBlockV2 groups the sandbox's capability grants. Today it carries
// only the network egress policy; it is the v2 home for what v1 spelled as the
// top-level caps: block.
type permissionsBlockV2 struct {
	Network *networkBlockV2 `yaml:"network,omitempty"`
}

// networkBlockV2 is the v2 canonical egress policy. It maps onto the internal
// Caps.Network allow/deny lists.
type networkBlockV2 struct {
	Allow []string `yaml:"allow,omitempty"`
	Deny  []string `yaml:"deny,omitempty"`
}

// resourcesV2 mirrors Resources but takes Memory as a byte-size string.
type resourcesV2 struct {
	CPU    float64 `yaml:"cpu,omitempty"`
	Memory string  `yaml:"memory,omitempty"`
	GPU    string  `yaml:"gpu,omitempty"`
}

// setupBlockV2 seeds files and runs install/startup commands. Files replaces
// the v1 commands.initFiles slice (same InitFile shape).
type setupBlockV2 struct {
	Install []InstallCommand `yaml:"install,omitempty"`
	Startup []StartupCommand `yaml:"startup,omitempty"`
	Files   []InitFile       `yaml:"files,omitempty"`
}

// commandFieldV2 is the polymorphic decode target for sandbox.command: either
// a sequence (shorthand: default only, interactive falls back to it) or a
// mapping {default, interactive}.
type commandFieldV2 struct {
	Default     []string
	Interactive []string
}

func (c *commandFieldV2) UnmarshalYAML(node *yaml.Node) error {
	switch node.Kind {
	case yaml.SequenceNode:
		return node.Decode(&c.Default)
	case yaml.MappingNode:
		var m struct {
			Default     []string `yaml:"default"`
			Interactive []string `yaml:"interactive"`
		}
		if err := node.Decode(&m); err != nil {
			return err
		}
		c.Default = m.Default
		c.Interactive = m.Interactive
		return nil
	case 0:
		return nil
	default:
		return fmt.Errorf("sandbox.command: must be a list (shorthand) or a mapping with default/interactive")
	}
}

// decodeSpecFileV2 decodes v2 spec.yaml bytes with strict field checking, so a
// v1 field appearing in a v2 spec is a hard error (and vice versa via the
// v1 decoder).
func decodeSpecFileV2(data []byte) (specFileV2, error) {
	var sf specFileV2
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(&sf); err != nil {
		return specFileV2{}, err
	}
	return sf, nil
}

// parseArtifactV2 decodes a schemaVersion "2" spec and maps it onto the
// canonical Artifact. It does not validate; callers that need a validated
// Artifact call ValidateArtifact themselves.
func parseArtifactV2(data []byte) (*Artifact, error) {
	sf, err := decodeSpecFileV2(data)
	if err != nil {
		return nil, fmt.Errorf("artifact: invalid %s: %w", specFileName, err)
	}
	w := &warnings{}
	art, err := sf.toArtifact(w)
	if err != nil {
		return nil, fmt.Errorf("artifact: %w", err)
	}
	art.Warnings = w.messages
	return art, nil
}

// toArtifact builds the canonical Artifact from a decoded v2 spec. It
// preserves Manifest.SchemaVersion = "2" (the binding-regime signal) and
// returns actionable errors for the block-placement rules mirrored from the
// v1 normalizer.
func (s *specFileV2) toArtifact(w *warnings) (*Artifact, error) {
	m := Manifest{
		SchemaVersion: s.SchemaVersion,
		Kind:          s.Kind,
		Name:          s.Name,
		Version:       s.Version,
		DisplayName:   s.DisplayName,
		Description:   s.Description,
		SourceURL:     s.SourceURL,
		Security:      s.Security,
		Volumes:       s.Volumes,
	}

	isSandbox := s.Kind == KindSandbox
	if s.Sandbox != nil && !isSandbox {
		return nil, fmt.Errorf("'sandbox:' block is only valid for kind %q, not %q", KindSandbox, s.Kind)
	}
	// A sandbox that extends a parent inherits the parent's image, so it may
	// omit its own sandbox block; only a root sandbox must supply one.
	if s.Sandbox == nil && isSandbox && s.Extends == "" {
		return nil, fmt.Errorf("kind %q requires a 'sandbox:' block with at least 'sandbox.image'", KindSandbox)
	}

	if s.Sandbox != nil {
		m.Template = s.Sandbox.Image
		m.Build = s.Sandbox.Build
		if s.Sandbox.Build != nil {
			w.notImplemented("sandbox.build", "Dockerfile builds are accepted in the schema but not yet built by the runtime; the image is taken from sandbox.image")
			if s.Sandbox.Image == "" {
				return nil, fmt.Errorf("sandbox.build is accepted in the schema but not yet implemented — specify sandbox.image")
			}
		}

		// entrypoint = fixed prefix (binary + always-on args); command tail
		// selects detached (default) vs interactive args.
		var tail []string
		if len(s.Sandbox.Entrypoint) > 0 {
			m.Binary = s.Sandbox.Entrypoint[0]
			tail = s.Sandbox.Entrypoint[1:]
		}
		interactive := s.Sandbox.Command.Interactive
		if interactive == nil {
			interactive = s.Sandbox.Command.Default
		}
		if def := concat(tail, s.Sandbox.Command.Default); len(def) > 0 {
			m.RunOptions = def
		}
		if inter := concat(tail, interactive); len(inter) > 0 {
			m.InteractiveOptions = inter
		}

		if s.Sandbox.Resources != nil {
			r := &Resources{CPU: s.Sandbox.Resources.CPU, GPU: s.Sandbox.Resources.GPU}
			if s.Sandbox.Resources.Memory != "" {
				b, err := units.RAMInBytes(s.Sandbox.Resources.Memory)
				if err != nil {
					return nil, fmt.Errorf("sandbox.resources.memory %q is not a valid size: %w", s.Sandbox.Resources.Memory, err)
				}
				r.MemoryMB = b / (1024 * 1024)
			}
			m.Resources = r
		}
	}

	if s.AgentInstructions != nil && s.AgentInstructions.Filename != "" {
		// filename names the AI profile the sandbox owns; a mixin only
		// contributes content, so its filename is ignored (not an error).
		if isSandbox {
			m.AIFilename = s.AgentInstructions.Filename
		} else {
			w.ignored("agentInstructions.filename", fmt.Sprintf("only used for kind %q, not %q", KindSandbox, s.Kind))
		}
	}

	if len(s.Mixins) > 0 {
		w.notImplemented("mixins", "mixin composition is accepted in the schema but not yet applied by the runtime")
	}

	art := &Artifact{
		Manifest:       m,
		Extends:        s.Extends,
		Mixins:         s.Mixins,
		Requires:       s.Requires,
		Locked:         s.Locked,
		Licenses:       s.Licenses,
		PublishedPorts: s.PublishedPorts,
		Environment:    s.Environment,
	}
	if s.AgentInstructions != nil {
		art.AgentContext = s.AgentInstructions.Content
	}

	if s.Permissions != nil && s.Permissions.Network != nil {
		net := s.Permissions.Network
		if len(net.Allow) > 0 || len(net.Deny) > 0 {
			art.Caps = &Caps{Network: &CapsNetwork{Allow: net.Allow, Deny: net.Deny}}
		}
	}

	if s.Setup != nil {
		art.Commands = &CommandsPolicy{
			Install:   s.Setup.Install,
			Startup:   s.Setup.Startup,
			InitFiles: s.Setup.Files,
		}
	}

	creds, err := expandCredentialSchemes(s.Credentials)
	if err != nil {
		return nil, err
	}
	art.Credentials = creds

	deriveProxyManagedEnvForArtifact(art)

	return art, nil
}

// expandCredentialSchemes rewrites the v2 `scheme:` sugar on apiKey inject
// entries into the canonical Format/Username fields, then clears Scheme so the
// normalized Artifact carries only the fields consumers already read. scheme
// and a raw format are mutually exclusive.
func expandCredentialSchemes(creds []Credential) ([]Credential, error) {
	for i := range creds {
		if creds[i].ApiKey == nil {
			continue
		}
		for j := range creds[i].ApiKey.Inject {
			inj := &creds[i].ApiKey.Inject[j]
			if inj.Scheme == "" {
				continue
			}
			if inj.Format != "" {
				return nil, fmt.Errorf("credentials[%d].apiKey.inject[%d]: 'scheme' and 'format' are mutually exclusive", i, j)
			}
			switch inj.Scheme {
			case "bearer":
				if inj.Username != "" {
					return nil, fmt.Errorf("credentials[%d].apiKey.inject[%d]: 'username' is not valid with scheme: bearer", i, j)
				}
				inj.Format = "Bearer %s"
			case "basic":
				if inj.Username == "" {
					return nil, fmt.Errorf("credentials[%d].apiKey.inject[%d]: scheme: basic requires 'username'", i, j)
				}
				// Basic auth is username-driven at the proxy; Format is a
				// placeholder so ValidateNetworkPolicy-style %s checks pass.
				inj.Format = "%s"
			default:
				return nil, fmt.Errorf("credentials[%d].apiKey.inject[%d]: unknown scheme %q (want \"basic\" or \"bearer\")", i, j, inj.Scheme)
			}
			inj.Scheme = ""
		}
	}
	return creds, nil
}

// deriveProxyManagedEnvForArtifact sets Environment.ProxyManaged to the names
// of credentials whose apiKey is marked ProxyManaged — the canonical
// in-container sentinel set. The v2 analogue of the v1 deriveProxyManagedEnv;
// it OVERRIDES any decoded list so the engine sees one source of truth.
func deriveProxyManagedEnvForArtifact(a *Artifact) {
	var names []string
	seen := map[string]bool{}
	for _, c := range a.Credentials {
		if c.ApiKey != nil && c.ApiKey.ProxyManaged && c.ApiKey.Name != "" && !seen[c.ApiKey.Name] {
			seen[c.ApiKey.Name] = true
			names = append(names, c.ApiKey.Name)
		}
	}
	sort.Strings(names)
	if len(names) == 0 {
		if a.Environment != nil {
			a.Environment.ProxyManaged = nil
		}
		return
	}
	if a.Environment == nil {
		a.Environment = &EnvironmentPolicy{}
	}
	a.Environment.ProxyManaged = names
}

// concat returns a fresh slice of prefix followed by tail (nil when both are
// empty), never aliasing either input.
func concat(prefix, tail []string) []string {
	if len(prefix) == 0 && len(tail) == 0 {
		return nil
	}
	out := make([]string, 0, len(prefix)+len(tail))
	out = append(out, prefix...)
	out = append(out, tail...)
	return out
}
