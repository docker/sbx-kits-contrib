// Package spec defines the declarative kit artifact format for Docker Sandboxes.
// Kit artifacts are directories containing a spec.yaml configuration file and an
// optional files/ directory with static files to inject into containers.
//
// This package provides types, loading, normalization, and validation for spec.yaml
// files. It is designed to be imported by both the public TCK (testcontainers-go
// based) and the internal sandboxes engine.
package spec

import (
	"bytes"
	"fmt"
	"io"
	"sort"

	"go.yaml.in/yaml/v3"
)

// SchemaVersion is the default schemaVersion used when a tool scaffolds
// a new kit. Stays at "1" while sbx releases v2-capable engines into
// the field; flip to "2" once enough consumers can read v2 artifacts to
// make it safe as a default. Authors who want v2 today set schemaVersion:
// "2" in their spec.yaml explicitly.
const SchemaVersion = "1"

// SupportedSchemaVersions enumerates every schemaVersion value the
// loader accepts. "1" is the legacy shape (the current default); "2"
// opts the kit into the v2 OCI artifact format at distribution time —
// the spec fields themselves are unchanged across the two versions.
//
// New entries should be appended (never reordered) so existing kits
// continue to validate.
var SupportedSchemaVersions = []string{"1", "2"}

// Kind constants for manifest types.
const (
	// KindSandbox defines a sandbox kit (must have a sandbox image source).
	// Only one sandbox kit is allowed per sandbox. Renamed from KindAgent
	// in schemaVersion "2"; v1 `kind: agent` is mapped to this value at
	// load time with a deprecation warning.
	KindSandbox = "sandbox"

	// KindAgent is the v1 alias for KindSandbox. Accepted at load time
	// with a deprecation warning. Drop in the Phase 4 schema-cutover
	// commit.
	KindAgent = "agent"

	// KindMixin defines an extension that adds capabilities.
	// Multiple mixins can coexist in a single sandbox.
	KindMixin = "mixin"
)

// ArtifactFile target constants.
const (
	// TargetHome means the file is copied relative to /home/agent/.
	TargetHome = "home"

	// TargetWorkspace means the file is copied relative to the workspace directory.
	TargetWorkspace = "workspace"
)

// Manifest represents the identity and metadata of an agent or kit artifact.
type Manifest struct {
	// SchemaVersion is the schema version, currently "1".
	SchemaVersion string `json:"schemaVersion" yaml:"schemaVersion"`

	// Kind is "agent" for full agents or "mixin" for extensions.
	Kind string `json:"kind" yaml:"kind"`

	// Name is a unique identifier (lowercase, alphanumeric + hyphens).
	Name string `json:"name" yaml:"name"`

	// Version is the kit's release version (e.g. "1.0", "2.3.1"). Optional;
	// when set, it is the source for the OCI annotation
	// vnd.docker.sandbox.kit.version at pack time.
	Version string `json:"version,omitempty" yaml:"version,omitempty"`

	// DisplayName is a human-readable name for display purposes.
	DisplayName string `json:"displayName,omitempty" yaml:"displayName,omitempty"`

	// Description is a short description of the agent or mixin.
	Description string `json:"description,omitempty" yaml:"description,omitempty"`

	// SourceURL is an optional URL to the kit's source repository or
	// documentation. When set, it is the source for the standard OCI
	// annotation org.opencontainers.image.source at pack time.
	SourceURL string `json:"sourceURL,omitempty" yaml:"sourceURL,omitempty"`

	// Binary is the executable binary name to run in the container.
	// Required for kind "agent", not used for kind "mixin".
	Binary string `json:"binary,omitempty" yaml:"binary,omitempty"`

	// Template is the Docker image reference for the agent's container.
	// Required for kind "agent", optional for kind "mixin".
	Template string `json:"template,omitempty" yaml:"template,omitempty"`

	// AIFilename is the AI profile markdown filename (e.g., "CLAUDE.md").
	AIFilename string `json:"aiFilename,omitempty" yaml:"aiFilename,omitempty"`

	// RunOptions are CLI arguments passed to the agent binary at startup.
	RunOptions []string `json:"runOptions,omitempty" yaml:"runOptions,omitempty"`

	// Resources optionally constrains container CPU, memory, and GPU.
	Resources *Resources `json:"resources,omitempty" yaml:"resources,omitempty"`

	// Build optionally describes how to build the sandbox image from a
	// Dockerfile, as an alternative to pulling a pre-built Template (image).
	// Forward-compat (RFC §490, P1): accepted at decode time so kits and the
	// published v2 docs can declare it, but NOT yet wired — the runtime does
	// not build images from this block in this release. A kit that sets
	// `build:` must still set `sandbox.image`; build-only kits are rejected at
	// load with an actionable error. See BuildConfig.
	Build *BuildConfig `json:"build,omitempty" yaml:"build,omitempty"`

	// Security defines container security settings.
	Security *Security `json:"security,omitempty" yaml:"security,omitempty"`

	// Volumes are mount entries in dash-style list form. Entries are
	// applied by Path. Each entry's Type selects the backing storage
	// (omit or set "" for the default block-backed volume; set "tmpfs"
	// for a RAM-backed mount).
	//
	// The yaml tag is "-" because the `volumes:` key is decoded at the
	// specFile level through volumesField — a polymorphic wrapper that
	// accepts both the v2 sequence shape and the v1 mapping shape (the
	// latter with a deprecation warning, folded into this slice by
	// normalize). Manifest stays the canonical Go-level destination.
	Volumes []MountSpec `json:"volumes,omitempty" yaml:"-"`
}

// TmpfsVolumes returns the subset of m.Volumes whose Type is
// MountTypeTmpfs. Convenience for call-sites that previously read the
// separate Manifest.Tmpfs field.
func (m *Manifest) TmpfsVolumes() []MountSpec {
	if len(m.Volumes) == 0 {
		return nil
	}
	out := make([]MountSpec, 0, len(m.Volumes))
	for _, v := range m.Volumes {
		if v.Type == MountTypeTmpfs {
			out = append(out, v)
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// Security defines container security settings for the sandbox.
type Security struct {
	// Privileged runs the container in privileged mode.
	Privileged bool `json:"privileged,omitempty" yaml:"privileged,omitempty"`
}

// MountType selects the backing storage for a MountSpec entry. Defined
// as a named type so downstream tooling (kit-generation helpers, etc.)
// can declare typed parameters instead of passing raw strings.
type MountType string

// Recognized MountType values.
const (
	// MountTypeBlock is the default block-backed volume. Encoded as the
	// empty string in YAML/JSON so existing entries that omit `type:`
	// continue to decode unchanged.
	MountTypeBlock MountType = ""

	// MountTypeTmpfs is a RAM-backed mount.
	MountTypeTmpfs MountType = "tmpfs"
)

// MountSpec is a single mount entry on Manifest.Volumes. Type selects
// the backing storage.
type MountSpec struct {
	// Path is the absolute mount path in the container.
	Path string `json:"path" yaml:"path"`

	// Type selects the backing storage. Defaults to MountTypeBlock
	// (block-backed); set MountTypeTmpfs for a RAM-backed mount. Added
	// in schemaVersion "2" to replace the separate top-level `tmpfs:`
	// block.
	Type MountType `json:"type,omitempty" yaml:"type,omitempty"`

	// Size is the mount size as a byte-size string (e.g., "100m", "4g",
	// "512m"). Optional.
	Size string `json:"size,omitempty" yaml:"size,omitempty"`

	// Mode is the mount mode in octal (e.g., "1777"). Optional.
	Mode string `json:"mode,omitempty" yaml:"mode,omitempty"`
}

// Resources describes optional container resource limits. All fields are
// optional; an unset field means "no constraint from the spec".
type Resources struct {
	// CPU is the number of CPU cores. Fractional values are allowed
	// (e.g. 0.5, 2.5).
	CPU float64 `json:"cpu,omitempty" yaml:"cpu,omitempty"`

	// MemoryMB is the memory limit in mebibytes.
	MemoryMB int64 `json:"memoryMB,omitempty" yaml:"memoryMB,omitempty"`

	// GPU is the GPU allocation as a string. Format is consumer-defined
	// (e.g. "1", "all", a vendor-specific selector).
	GPU string `json:"gpu,omitempty" yaml:"gpu,omitempty"`
}

// BuildConfig describes how to build a container image from a Dockerfile,
// an alternative to referencing a pre-built image (RFC §490, P1).
//
// Forward-compat only: this block is accepted at decode time so kit authors
// and the published v2 docs can declare it, but the runtime does NOT build
// images from it in this release. A kit that sets `build:` must still set
// `sandbox.image` (the image is the source of truth this release); a
// build-only kit is rejected at load with an actionable error. When the
// build path lands, omitted fields take their documented defaults
// (Context ".", Dockerfile "Dockerfile") — defaults are intentionally not
// applied here so the decoded form round-trips exactly as written.
type BuildConfig struct {
	// Context is the build context directory, relative to spec.yaml.
	// Default "." when the build path is implemented.
	Context string `json:"context,omitempty" yaml:"context,omitempty"`

	// Dockerfile is the Dockerfile path, relative to Context.
	// Default "Dockerfile" when the build path is implemented.
	Dockerfile string `json:"dockerfile,omitempty" yaml:"dockerfile,omitempty"`

	// Args are build arguments passed to `docker build --build-arg`.
	Args map[string]string `json:"args,omitempty" yaml:"args,omitempty"`

	// Target selects a multi-stage build target.
	Target string `json:"target,omitempty" yaml:"target,omitempty"`

	// Platforms lists target platforms (e.g. "linux/amd64", "linux/arm64").
	Platforms []string `json:"platforms,omitempty" yaml:"platforms,omitempty"`
}

// NetworkPolicy defines network rules for which external domains the agent
// communicates with and how to authenticate.
type NetworkPolicy struct {
	// ServiceDomains maps domain patterns to service identifiers for proxy routing.
	ServiceDomains map[string]string `json:"serviceDomains,omitempty" yaml:"serviceDomains,omitempty"`

	// ServiceAuth maps service identifiers to authentication header configuration.
	ServiceAuth map[string]ServiceAuth `json:"serviceAuth,omitempty" yaml:"serviceAuth,omitempty"`

	// AllowedDomains is an explicit allowlist of domains the agent may access.
	AllowedDomains []string `json:"allowedDomains,omitempty" yaml:"allowedDomains,omitempty"`

	// DeniedDomains is an explicit denylist of domains the agent must not access.
	// Deny rules take precedence over allow rules at policy evaluation time, so a
	// kit can lock its sandbox out of specific domains regardless of presets or
	// other allow lists contributed by composed kits.
	DeniedDomains []string `json:"deniedDomains,omitempty" yaml:"deniedDomains,omitempty"`

	// PublishedPorts is the v1 location for declared ports
	// (`network.publishedPorts`). In v2 this moved to the top-level
	// `publishedPorts:` field; normalize promotes this shim there with a
	// deprecation warning. Retained only so v1 spec.yaml still decodes
	// under strict (KnownFields) decoding. Removed in the Phase 6 cutover.
	//
	// See PublishedPort and Artifact.PublishedPorts for the semantics
	// (ephemeral host port on 127.0.0.1; `sbx ports --publish` for pinning).
	PublishedPorts []PublishedPort `json:"publishedPorts,omitempty" yaml:"publishedPorts,omitempty"`
}

// PublishedPort declares an in-container port that the sandbox runtime
// should publish on the host when the sandbox starts. Host port allocation
// is always ephemeral; callers wire the assigned port at runtime by
// listing the sandbox's published bindings.
type PublishedPort struct {
	// Container is the in-container TCP/UDP port the service listens on.
	// Required. Must be in 1..65535.
	Container int `json:"container" yaml:"container"`

	// Protocol is "tcp" or "udp". Optional; defaults to "tcp" if empty.
	Protocol string `json:"protocol,omitempty" yaml:"protocol,omitempty"`

	// Name is an optional human-readable label for the port, surfaced by
	// tools that list a sandbox's published ports (`sbx ports`). Two kits
	// may declare ports with the same name without conflict — the name
	// is informational, not an identifier.
	Name string `json:"name,omitempty" yaml:"name,omitempty"`
}

// ServiceAuth defines how to format authentication headers for a service.
type ServiceAuth struct {
	// HeaderName is the HTTP header name (e.g., "Authorization", "x-api-key").
	HeaderName string `json:"headerName" yaml:"headerName"`

	// ValueFormat is a format string for the header value (e.g., "Bearer %s", "%s").
	ValueFormat string `json:"valueFormat" yaml:"valueFormat"`
}

// CredentialPolicy is the v1 `credentials:` block shape (mapping with
// `sources:` inside). Kept as a deserialization target for the
// credentialsField polymorphic wrapper on specFile; normalize folds its
// contents into the canonical Artifact.Credentials []Credential list with
// a deprecation warning. Removed in the Phase 6 schema cutover.
type CredentialPolicy struct {
	// Sources maps service identifiers to credential source definitions.
	Sources map[string]CredentialSource `json:"sources,omitempty" yaml:"sources,omitempty"`
}

// Credential is one credential the kit declares it needs. The kit
// describes WHAT it needs (service identity, where to inject the
// resolved value); the user-side bindings file
// (~/.config/sbx/credentials.yaml) is the sole source for WHERE the
// credential lives.
type Credential struct {
	// Service is the canonical service identifier (e.g., "anthropic",
	// "openai", "github"). Must match the lowercase-kebab pattern.
	Service string `json:"service" yaml:"service"`

	// Description is a free-text label surfaced in interactive prompts
	// when the resolver needs to ask the user which binding to create.
	Description string `json:"description,omitempty" yaml:"description,omitempty"`

	// Required marks the credential as essential for the agent to function.
	// The resolver fails fast (rather than continuing with the credential
	// unset) when a required entry has no binding and no host fallback.
	Required bool `json:"required,omitempty" yaml:"required,omitempty"`

	// Provider is a forward-compat stub for the future provider registry
	// (`provider: anthropic` -> standard injection config). Setting this
	// field emits a deprecation-style warning at load time and has no
	// runtime effect in this release. See the v2 design doc's deferred
	// list for the registry roadmap.
	Provider string `json:"provider,omitempty" yaml:"provider,omitempty"`

	// ApiKey describes the api-key-shaped half of this credential, if any.
	ApiKey *ApiKey `json:"apiKey,omitempty" yaml:"apiKey,omitempty"`

	// OAuth describes the OAuth-shaped half of this credential, if any.
	// A credential can declare both ApiKey and OAuth; when both resolve at
	// runtime the API key takes precedence (per-VM key over the OAuth token).
	OAuth *OAuth `json:"oauth,omitempty" yaml:"oauth,omitempty"`
}

// RoutingHosts returns every host the proxy must route to this credential's
// service: apiKey injection domains, the OAuth token-refresh endpoint, and
// OAuth resource hosts. Deduplicated and sorted for deterministic output.
// This is the full routing set; it is NOT the binding-gate set (the gate uses
// apiKey injection domains only).
func (c Credential) RoutingHosts() []string {
	seen := map[string]bool{}
	var hosts []string
	add := func(h string) {
		if h == "" || seen[h] {
			return
		}
		seen[h] = true
		hosts = append(hosts, h)
	}
	if c.ApiKey != nil {
		for _, inj := range c.ApiKey.Inject {
			add(inj.Domain)
		}
	}
	if c.OAuth != nil {
		add(c.OAuth.TokenEndpoint.Host)
		for _, h := range c.OAuth.ResourceHosts {
			add(h)
		}
	}
	sort.Strings(hosts)
	return hosts
}

// ApiKey describes an api-key-shaped credential. Inject is the fan-out
// of which domains/headers the proxy injects the resolved value into;
// Name is the env-var name the proxy populates inside the container
// (set to the literal "proxy-managed" by the engine when this credential
// is wired up).
type ApiKey struct {
	Name string `json:"name" yaml:"name"`
	// ProxyManaged, when true, makes the engine set Name to the literal
	// "proxy-managed" sentinel inside the container (the sentinel-swap proxy
	// replaces it on the matching inject domains). Default false: a credential
	// is injected by the proxy on its domains but its env var is NOT set
	// in-container unless this is set. Re-expresses the removed v1
	// environment.proxyManaged list per-credential.
	ProxyManaged bool           `json:"proxyManaged,omitempty" yaml:"proxyManaged,omitempty"`
	Inject       []ApiKeyInject `json:"inject,omitempty" yaml:"inject,omitempty"`
}

// ApiKeyInject describes one (domain, header) injection rule for an
// api-key credential. Format must contain exactly one %s where the
// resolved credential value is substituted.
type ApiKeyInject struct {
	Domain string `json:"domain" yaml:"domain"`
	Header string `json:"header" yaml:"header"`
	Format string `json:"format" yaml:"format"`

	// Username is set when the injection is HTTP Basic Auth — the proxy
	// uses this string as the username and the resolved credential value
	// as the password. Used by the github kit for git HTTPS clone
	// (`x-access-token` as the literal username).
	Username string `json:"username,omitempty" yaml:"username,omitempty"`
}

// CredentialSource defines how to discover a credential for a specific service.
type CredentialSource struct {
	// Env lists environment variable names to check (in order of priority).
	Env []string `json:"env,omitempty" yaml:"env,omitempty"`

	// File defines a file-based credential source.
	File *FileCredentialSource `json:"file,omitempty" yaml:"file,omitempty"`

	// Priority determines lookup order: "env-first" (default) or "file-first".
	Priority string `json:"priority,omitempty" yaml:"priority,omitempty"`

	// Required indicates that this credential is essential for the agent to function.
	Required bool `json:"required,omitempty" yaml:"required,omitempty"`
}

// FileCredentialSource defines a file-based credential location on the host.
type FileCredentialSource struct {
	// Path is the file path on the host (~ is expanded to home directory).
	Path string `json:"path" yaml:"path"`

	// Parser describes how to extract the credential value from the file.
	Parser string `json:"parser,omitempty" yaml:"parser,omitempty"`
}

// Caps is the v2 top-level capability block. Phase 3 commit 6 introduces
// caps.network as the canonical home for the egress allow/deny lists
// (previously network.allowedDomains / network.deniedDomains). Future
// caps surfaces (caps.filesystem and so on, RFC §82x) attach here.
type Caps struct {
	Network *CapsNetwork `json:"network,omitempty" yaml:"network,omitempty"`
}

// CapsNetwork declares which external domains the sandbox is allowed to
// reach (Allow) and which are denied (Deny). Deny takes precedence over
// Allow at policy evaluation time. P2 entry formats (this release):
//
//   - exact:                 api.example.com
//   - exact:port:            api.example.com:443
//   - single-label wildcard: *.example.com
//
// P3 entry formats (deferred): double wildcards (**.example.com), CIDR
// (10.0.0.0/8), port ranges (api.example.com:8000-9000).
type CapsNetwork struct {
	Allow []string `json:"allow,omitempty" yaml:"allow,omitempty"`
	Deny  []string `json:"deny,omitempty" yaml:"deny,omitempty"`
}

// Requires declares composition preconditions for a kit. Today it carries
// only base-agent affinity — the base agent a mixin is designed to layer onto.
// Env vars, credentials, and settings a mixin injects are often agent-specific
// (e.g. Claude Code's ANTHROPIC_* variables mean nothing to a codex sandbox),
// so a mixin can pin the base agent it makes sense on.
//
// The spec library validates only well-formedness; enforcement — rejecting a
// mixin applied to a non-matching base agent — lives in the consumer that
// performs composition, alongside Locked and Licenses.
type Requires struct {
	// Agent is the base-agent name this kit is designed for. When set,
	// composing the kit onto a different base agent is a composition error.
	// Absent or empty means the kit declares no affinity and layers onto any
	// base agent. A single agent, not a set: affinity exists to prevent
	// misapplication, and an "any of these" set would defeat that guarantee.
	// Broader family matching (claude and its claude-* variants) is left to
	// the consumer's extends-lineage check, not an explicit list.
	Agent string `json:"agent,omitempty" yaml:"agent,omitempty"`
}

// EnvironmentPolicy defines environment variables to set in the container.
type EnvironmentPolicy struct {
	// Variables are static environment variables to set in the container.
	Variables map[string]string `json:"variables,omitempty" yaml:"variables,omitempty"`

	// ProxyManaged absorbs the v1 `environment.proxyManaged` list.
	// The normalize step folds each entry into the matching
	// Credentials[].ApiKey.Name (by service lookup against
	// LegacyNetwork.ServiceAuth) and emits a deprecation warning.
	// Removed in the Phase 6 schema cutover.
	ProxyManaged []string `json:"-" yaml:"proxyManaged,omitempty"`
}

// SettingsPolicy defines container settings that control agent-specific
// configuration file creation. As of Phase 4 it is no longer a canonical
// Artifact surface — it survives only as the decode target for the
// specFile.LegacySettings shim (the v1 `settings:` block), which
// normalizeLegacySettings absorbs-and-drops with a deprecation warning.
// Removed in the Phase 6 schema cutover.
type SettingsPolicy struct {
	// ContainerSettings controls which agent-container settings files are created.
	ContainerSettings map[string]bool `json:"containerSettings,omitempty" yaml:"containerSettings,omitempty"`
}

// CommandsPolicy defines install commands, startup commands, file initialization,
// and runtime configuration.
type CommandsPolicy struct {
	// Install lists commands to install the agent binary.
	Install []InstallCommand `json:"install,omitempty" yaml:"install,omitempty"`

	// Startup lists commands to run at container startup.
	Startup []StartupCommand `json:"startup,omitempty" yaml:"startup,omitempty"`

	// InitFiles lists files to create at container startup.
	InitFiles []InitFile `json:"initFiles,omitempty" yaml:"initFiles,omitempty"`
}

// InstallCommand defines a shell command to install the agent binary.
type InstallCommand struct {
	// Command is the shell command string (passed to "sh -c").
	Command string `json:"command" yaml:"command"`

	// User is the user to run the command as (default "0").
	User string `json:"user,omitempty" yaml:"user,omitempty"`

	// Description is a human-readable description of what this command does.
	Description string `json:"description,omitempty" yaml:"description,omitempty"`
}

// StartupCommand defines a command to run at container startup.
type StartupCommand struct {
	// Command is the command and its arguments.
	Command []string `json:"command" yaml:"command"`

	// User is the user to run the command as (default "1000").
	User string `json:"user,omitempty" yaml:"user,omitempty"`

	// Background runs the command in the background if true.
	Background bool `json:"background,omitempty" yaml:"background,omitempty"`

	// Description is a human-readable description of what this command does.
	Description string `json:"description,omitempty" yaml:"description,omitempty"`
}

// InitFile defines a file to create at container startup.
type InitFile struct {
	// Path is the absolute path in the container where the file is created.
	Path string `json:"path" yaml:"path"`

	// Content is the file content (inline string).
	Content string `json:"content" yaml:"content"`

	// Mode is the file permissions in octal (default "0644").
	Mode string `json:"mode,omitempty" yaml:"mode,omitempty"`

	// OnlyIfMissing creates the file only if it doesn't already exist.
	OnlyIfMissing bool `json:"onlyIfMissing,omitempty" yaml:"onlyIfMissing,omitempty"`

	// Description is a human-readable description of the file's purpose.
	Description string `json:"description,omitempty" yaml:"description,omitempty"`
}

// ArtifactFile represents a file from the artifact's files/ directory
// to be copied into the container.
type ArtifactFile struct {
	// RelativePath is the path relative to the target root (home/ or workspace/).
	RelativePath string `json:"relativePath"`

	// Target is the destination root: "home" or "workspace".
	Target string `json:"target"`

	// Mode is the file permissions (default 0644).
	Mode int64 `json:"mode"`

	// Content holds the raw file bytes. Eager loaders (LoadFromDirectory,
	// LoadFromFS) populate this field; streaming loaders
	// (OpenFromDirectory, OpenFromFS) leave it nil and set ContentSource
	// instead. Content is always non-nil (even for empty files) on the
	// eager path. LoadArtifactFromBytes never populates Content (it has no notion
	// of a file source; callers populate Files from their own source).
	Content []byte `json:"content"`

	// Size is the file size in bytes.
	Size int64 `json:"size"`

	// ContentSource streams this file's content on demand. Streaming loaders
	// set it; eager loaders leave it nil. The tag json:"-" ensures that
	// a function value — which is not JSON-serializable — is always omitted
	// from marshaling. Call Open to obtain a reader regardless of which
	// loading strategy was used.
	ContentSource func() (io.ReadCloser, error) `json:"-"`
}

// Open returns a reader for this file's content. It follows this precedence:
//   - If Content is non-nil (eager path), returns a reader backed by Content.
//   - Otherwise, if ContentSource is non-nil (streaming path), calls it.
//   - If neither is set, returns an error.
//
// Callers are responsible for closing the returned ReadCloser. Calling Open
// multiple times on a streaming file yields independent readers.
func (f *ArtifactFile) Open() (io.ReadCloser, error) {
	if f.Content != nil {
		return io.NopCloser(bytes.NewReader(f.Content)), nil
	}
	if f.ContentSource != nil {
		return f.ContentSource()
	}
	return nil, fmt.Errorf("artifact file %q: no content or content source", f.RelativePath)
}

// Artifact represents a fully loaded and validated kit artifact.
type Artifact struct {
	// Manifest is the required agent/plugin identity and metadata.
	Manifest Manifest `json:"manifest"`

	// Extends is the optional parent kit name for single-parent inheritance.
	Extends string `json:"extends,omitempty"`

	// Mixins lists horizontal-composition components applied after the
	// extends chain resolves (RFC §362, P1). Forward-compat: accepted at
	// decode time so kits and the published v2 docs can declare it, but
	// mixin composition is not wired in this release — the field has no
	// runtime effect yet (a load-time warning fires when it is used).
	Mixins []string `json:"mixins,omitempty"`

	// Requires declares composition preconditions — currently base-agent
	// affinity (see Requires). The spec library validates well-formedness;
	// enforcement lives in the consumer that performs composition.
	Requires *Requires `json:"requires,omitempty"`

	// Locked lists dotted YAML paths (e.g. "agent.image") on this artifact
	// that child kits must not override during single-parent inheritance.
	// The spec library only validates well-formedness; enforcement lives
	// in the consumer that performs the merge.
	Locked []string `json:"locked,omitempty"`

	// Licenses lists SPDX license identifiers governing the kit (RFC §280,
	// P2). The spec library only validates well-formedness; composition
	// (union of parent/mixin licenses) lives in the consumer that performs
	// the merge. Declarative metadata with no runtime effect.
	Licenses []string `json:"licenses,omitempty"`

	// PublishedPorts lists in-container ports the kit wants the runtime to
	// publish on the host when the sandbox starts. It is a top-level
	// canonical field in v2 — port publishing is inbound service exposure,
	// a separate concern from the outbound egress policy under Caps.Network.
	// The v1 `network.publishedPorts` location is promoted here by normalize
	// with a deprecation warning.
	PublishedPorts []PublishedPort `json:"publishedPorts,omitempty"`

	// Caps is the v2 capabilities block. caps.network is the canonical
	// home for egress allow/deny lists; future caps.* surfaces attach
	// here.
	Caps *Caps `json:"caps,omitempty"`

	// Credentials is the unified credential list (one entry per service)
	// populated by normalize. v2 spec.yaml decodes directly into this
	// slice; v1 spec.yaml has its credentials.sources / network.serviceAuth /
	// network.serviceDomains / environment.proxyManaged / standalone oauth:
	// shapes folded together into one Credential per service with a
	// deprecation warning per legacy block touched.
	Credentials []Credential `json:"credentials,omitempty"`

	// Environment is the optional environment policy.
	Environment *EnvironmentPolicy `json:"environment,omitempty"`

	// Commands is the optional startup commands and init files.
	Commands *CommandsPolicy `json:"commands,omitempty"`

	// Files are static files from the files/ directory to copy into the container.
	Files []ArtifactFile `json:"files,omitempty"`

	// AgentContext is optional agent-specific markdown content appended to
	// the AI profile file. Renamed from `Memory` in schemaVersion "2";
	// v1 `memory:` is mapped to this field at load time with a deprecation
	// warning.
	AgentContext string `json:"agentContext,omitempty"`

	// Warnings is the list of non-fatal validation issues collected during
	// load (typically v1 → v2 deprecation warnings). Empty slice when the
	// spec uses only canonical v2 fields.
	Warnings []string `json:"warnings,omitempty"`
}

// OAuthPolicy is the v1 standalone top-level `oauth:` block shape. Kept
// as a deserialization target for specFile.LegacyOAuth; normalize folds
// it into Credentials[].OAuth with a deprecation warning. Removed in the
// Phase 6 schema cutover.
type OAuthPolicy struct {
	Service             string               `json:"service" yaml:"service"`
	TokenEndpoint       OAuthTokenEndpoint   `json:"tokenEndpoint" yaml:"tokenEndpoint"`
	Sentinels           OAuthSentinels       `json:"sentinels" yaml:"sentinels"`
	CredentialFile      *OAuthCredentialFile `json:"credentialFile,omitempty" yaml:"credentialFile,omitempty"`
	SkipIfEnv           []string             `json:"skipIfEnv,omitempty" yaml:"skipIfEnv,omitempty"`
	ResponseFields      *OAuthResponseFields `json:"responseFields,omitempty" yaml:"responseFields,omitempty"`
	PassthroughResponse bool                 `json:"passthroughResponse,omitempty" yaml:"passthroughResponse,omitempty"`
}

// OAuth is the v2 per-credential OAuth sub-shape. Same fields as OAuthPolicy
// minus Service (the service identifier comes from the parent Credential),
// and with Passthrough replacing PassthroughResponse (renamed; same
// semantics — Passthrough = true opts out of sentinel masking, a security
// downgrade flagged with a warning at load time).
//
// A `passthroughReason: ...` field is deliberately NOT included in this
// release. Whether passthrough should require a documented justification is
// a design question we want to revisit later; if added in a future schema
// version, existing kits using only `passthrough: true` would have to add
// the reason.
type OAuth struct {
	TokenEndpoint OAuthTokenEndpoint `json:"tokenEndpoint" yaml:"tokenEndpoint"`
	// ResourceHosts are the API hosts where the OAuth access-token bearer is
	// used (e.g. "aiplatform.googleapis.com"). The proxy routes these hosts to
	// this service and substitutes the sentinel bearer for the real token.
	// Distinct from TokenEndpoint.Host (where the token is refreshed). Domains
	// only — the bearer header is uniform (Authorization: Bearer) and supplied
	// by the OAuth engine, not per-host config.
	ResourceHosts  []string             `json:"resourceHosts,omitempty" yaml:"resourceHosts,omitempty"`
	Sentinels      OAuthSentinels       `json:"sentinels" yaml:"sentinels"`
	CredentialFile *OAuthCredentialFile `json:"credentialFile,omitempty" yaml:"credentialFile,omitempty"`
	SkipIfEnv      []string             `json:"skipIfEnv,omitempty" yaml:"skipIfEnv,omitempty"`
	ResponseFields *OAuthResponseFields `json:"responseFields,omitempty" yaml:"responseFields,omitempty"`
	Passthrough    bool                 `json:"passthrough,omitempty" yaml:"passthrough,omitempty"`
}

// OAuthResponseFields maps logical OAuth token field names to the actual
// JSON field names returned by the token endpoint.
type OAuthResponseFields struct {
	AccessToken  string `json:"accessToken,omitempty" yaml:"accessToken,omitempty"`
	RefreshToken string `json:"refreshToken,omitempty" yaml:"refreshToken,omitempty"`
	ExpiresIn    string `json:"expiresIn,omitempty" yaml:"expiresIn,omitempty"`
	Scope        string `json:"scope,omitempty" yaml:"scope,omitempty"`
}

// OAuthTokenEndpoint identifies the OAuth token URL by host and path.
type OAuthTokenEndpoint struct {
	Host string `json:"host" yaml:"host"`
	Path string `json:"path" yaml:"path"`
}

// OAuthSentinels defines the sentinel token values that replace real tokens
// in responses to the sandbox.
type OAuthSentinels struct {
	AccessToken  string `json:"accessToken" yaml:"accessToken"`
	RefreshToken string `json:"refreshToken" yaml:"refreshToken"`
}

// OAuthCredentialFile defines how to render and inject an OAuth credential
// file into the container at startup.
//
// Two render shapes are supported:
//   - Template (v1): a Go text/template string rendered with OAuthTemplateData.
//     Free-form string output; prone to injection attacks when token values
//     contain quotes/braces. Kept for back-compat; deprecated.
//   - Structure (v2): a declarative JSON shape with `{{.AccessToken}}`-style
//     placeholders that the engine substitutes at runtime. Output is
//     guaranteed to be well-formed JSON because the shape is encoded as a
//     Go map before placeholder substitution. Preferred for new kits.
//
// When both are set, Structure wins and Template is ignored with a
// deprecation warning. Phase 6 removes Template.
type OAuthCredentialFile struct {
	Path      string                 `json:"path" yaml:"path"`
	Template  string                 `json:"template,omitempty" yaml:"template,omitempty"`
	Structure map[string]interface{} `json:"structure,omitempty" yaml:"structure,omitempty"`
}

// OAuthTemplateData is the data passed to OAuthCredentialFile.Template.
type OAuthTemplateData struct {
	AccessToken  string
	RefreshToken string
	ExpiresAt    int64
	Scopes       []string
	ScopesJSON   string
}

// ResolvedResponseFields returns the response field mapping with defaults applied.
func (p *OAuthPolicy) ResolvedResponseFields() OAuthResponseFields {
	fields := OAuthResponseFields{
		AccessToken:  "access_token",
		RefreshToken: "refresh_token",
		ExpiresIn:    "expires_in",
		Scope:        "scope",
	}
	if p.ResponseFields != nil {
		if p.ResponseFields.AccessToken != "" {
			fields.AccessToken = p.ResponseFields.AccessToken
		}
		if p.ResponseFields.RefreshToken != "" {
			fields.RefreshToken = p.ResponseFields.RefreshToken
		}
		if p.ResponseFields.ExpiresIn != "" {
			fields.ExpiresIn = p.ResponseFields.ExpiresIn
		}
		if p.ResponseFields.Scope != "" {
			fields.Scope = p.ResponseFields.Scope
		}
	}
	return fields
}

// SpecFile is the on-disk YAML schema for spec.yaml.
type SpecFile struct {
	Manifest `yaml:",inline"`
	// Volumes is the polymorphic-decode wrapper for the `volumes:` YAML
	// key, handling both the v1 mapping shape and the v2 sequence shape.
	// Manifest.Volumes carries `yaml:"-"` so this field owns the decode;
	// normalize folds Volumes.List + Volumes.LegacyMap into the canonical
	// Manifest.Volumes slice.
	Volumes  volumesField  `yaml:"volumes,omitempty"`
	Extends  string        `yaml:"extends,omitempty"`
	Mixins   []string      `yaml:"mixins,omitempty"`
	Requires *Requires     `yaml:"requires,omitempty"`
	Locked   []string      `yaml:"locked,omitempty"`
	Licenses []string      `yaml:"licenses,omitempty"`
	Sandbox  *sandboxBlock `yaml:"sandbox,omitempty"`
	// LegacyAgent holds the v1 `agent:` block. The normalize step
	// migrates its contents to Sandbox with a deprecation warning. Drop
	// in the Phase 6 schema-cutover commit.
	LegacyAgent *sandboxBlock     `yaml:"agent,omitempty"`
	Secrets     []string          `yaml:"secrets,omitempty"`
	Egress      map[string]string `yaml:"egress,omitempty"`
	// Credentials is the polymorphic-decode wrapper handling both v1
	// (mapping with sources:) and v2 (sequence of Credential) shapes.
	// normalizeLegacyCredentials folds the v1 surface plus the
	// LegacyNetwork / LegacyOAuth / Environment.ProxyManaged
	// shims into Artifact.Credentials.
	Credentials credentialsField `yaml:"credentials,omitempty"`
	// PublishedPorts is the v2 canonical top-level `publishedPorts:` list.
	// Decoded directly from YAML; normalize also promotes the v1
	// LegacyNetwork.PublishedPorts shim into this slice.
	PublishedPorts []PublishedPort `yaml:"publishedPorts,omitempty"`
	// LegacyNetwork absorbs the v1 top-level `network:` block. normalize
	// folds its serviceDomains/serviceAuth fields into Credentials, its
	// allowedDomains/deniedDomains into Caps.Network, and its publishedPorts
	// into the top-level PublishedPorts. Removed in the Phase 6 schema cutover.
	LegacyNetwork *NetworkPolicy     `yaml:"network,omitempty"`
	Environment   *EnvironmentPolicy `yaml:"environment,omitempty"`
	// LegacySettings absorbs the v1 `settings:` block. There is no v2 field
	// to map it into — the container-settings behavior was lifted into each
	// kit's initFiles/commands.startup (Phase 4) — so normalizeLegacySettings
	// drops it with a deprecation warning. Kept only so KnownFields(true)
	// strict decode still admits a stray `settings:` block instead of hard-
	// rejecting it. Removed in the Phase 6 schema cutover.
	LegacySettings *SettingsPolicy `yaml:"settings,omitempty"`
	Commands       *CommandsPolicy `yaml:"commands,omitempty"`
	// Caps is the v2 capabilities block (caps.network and any future
	// caps.* surfaces). Decoded directly from YAML; the normalize step
	// also populates Caps.Network from the v1 network.allowedDomains/
	// deniedDomains shim (LegacyNetwork) when those are present.
	Caps *Caps `yaml:"caps,omitempty"`
	// LegacyOAuth absorbs the v1 standalone top-level `oauth:` block.
	// normalize folds it into Credentials[].OAuth (matched by service)
	// or synthesizes a new Credential entry if no entry exists for its
	// service yet. Removed in the Phase 6 schema cutover.
	LegacyOAuth  *OAuthPolicy `yaml:"oauth,omitempty"`
	AgentContext string       `yaml:"agentContext,omitempty"`
	// LegacyMemory holds the v1 `memory:` field. The normalize step
	// migrates it to AgentContext with a deprecation warning. Drop in
	// the Phase 6 schema-cutover commit.
	LegacyMemory string `yaml:"memory,omitempty"`
	// LegacyPersistence holds the v1 `persistence:` field. The field was
	// declared, parsed, inherited, displayed, but never consumed by any
	// runtime decision (see sandboxes commit 05e5b4eef adopting PR #37).
	// It was removed from the canonical types in PR #37, but that same PR
	// also flipped on strict YAML decoding — turning what had been a silent
	// no-op into a hard error for any kit author whose spec still carried
	// the line. The normalize step now drops it with a deprecation warning
	// to give those kits one release to migrate. Drop in the Phase 6
	// schema-cutover commit.
	LegacyPersistence string `yaml:"persistence,omitempty"`
	// LegacyKitDir holds the v1 `kitDir:` field. Same story as
	// LegacyPersistence — declared but never consumed, removed in PR #37,
	// re-admitted here as a deprecation-warning shim. Drop in the Phase 6
	// schema-cutover commit.
	LegacyKitDir string `yaml:"kitDir,omitempty"`
	// LegacyTmpfs holds the v1 `tmpfs:` block as a mapping from container
	// path to size string (e.g. `{ /tmp/scratch: "512m" }`). The v1 shape
	// was first replaced by `Tmpfs []MountSpec` (PR #37) and then deleted
	// entirely by PR #59 in favor of `volumes:` entries with `type: tmpfs`.
	// The strict-decode flip turned a no-op into a hard rejection;
	// normalize folds entries into Manifest.Volumes with Type=Tmpfs and
	// emits a deprecation warning. Drop in the Phase 6 schema-cutover
	// commit.
	LegacyTmpfs map[string]string `yaml:"tmpfs,omitempty"`
}

// credentialsField is the specFile-level polymorphic wrapper for the
// `credentials:` YAML key. It handles both v1 (mapping with sources:
// inside) and v2 (sequence of Credential) shapes. The normalize step
// reads LegacySources (if present) plus the Legacy fields under network:
// and environment:, constructs []Credential, and stores into
// Artifact.Credentials.
//
// Phase 1's two-yaml-tag pattern (used for memory/agentContext and
// agent/sandbox) doesn't apply here because v1 and v2 share the same
// `credentials:` YAML tag with different value kinds — only a custom
// UnmarshalYAML can disambiguate.
type credentialsField struct {
	// List is populated when credentials: is a sequence (v2 spelling).
	List []Credential

	// LegacySources is populated when credentials: is a mapping with
	// sources: under it (v1 spelling). Each entry carries the env/file
	// discovery hints the v1 shape used.
	LegacySources map[string]CredentialSource
}

func (c *credentialsField) UnmarshalYAML(node *yaml.Node) error {
	switch node.Kind {
	case yaml.SequenceNode:
		return node.Decode(&c.List)
	case yaml.MappingNode:
		var v1 struct {
			Sources map[string]CredentialSource `yaml:"sources"`
		}
		if err := node.Decode(&v1); err != nil {
			return err
		}
		c.LegacySources = v1.Sources
		return nil
	case 0:
		return nil
	default:
		return fmt.Errorf("credentials: must be a list (v2) or a mapping with sources: (v1)")
	}
}

func (c credentialsField) MarshalYAML() (interface{}, error) {
	if len(c.LegacySources) > 0 {
		return map[string]any{"sources": c.LegacySources}, nil
	}
	if len(c.List) == 0 {
		return nil, nil
	}
	return c.List, nil
}

// volumesField is the specFile-level polymorphic wrapper for the `volumes:`
// YAML key. PR #37 replaced the v1 mapping shape
// (`volumes: { /path: "size" }`) with the v2 sequence shape
// (`volumes: [{ path: /path, size: "100m" }]`), then flipped on strict
// decoding in the same commit. Strict decode hard-fails the v1 mapping
// shape with a type-mismatch error rather than a "field not found"; this
// wrapper accepts both shapes and lets normalize fold the legacy form into
// Manifest.Volumes with a deprecation warning.
type volumesField struct {
	// List is populated when volumes: is a sequence (v2 spelling).
	List []MountSpec

	// LegacyMap is populated when volumes: is a mapping (v1 spelling):
	// each key is the container mount path, each value is a size string
	// (or empty when the v1 spec carried no size).
	LegacyMap map[string]string
}

func (v *volumesField) UnmarshalYAML(node *yaml.Node) error {
	switch node.Kind {
	case yaml.SequenceNode:
		return node.Decode(&v.List)
	case yaml.MappingNode:
		var m map[string]string
		if err := node.Decode(&m); err != nil {
			return err
		}
		v.LegacyMap = m
		return nil
	case 0:
		return nil
	default:
		return fmt.Errorf("volumes: must be a list (v2) or a mapping (v1)")
	}
}

func (v volumesField) MarshalYAML() (interface{}, error) {
	if len(v.LegacyMap) > 0 {
		return v.LegacyMap, nil
	}
	if len(v.List) == 0 {
		return nil, nil
	}
	return v.List, nil
}

// sandboxBlock groups sandbox-specific configuration (formerly the
// `agent:` block in v1). The Go type was renamed alongside the YAML
// field rename to keep call sites legible.
type sandboxBlock struct {
	Image      string           `yaml:"image,omitempty"`
	Build      *BuildConfig     `yaml:"build,omitempty"`
	Entrypoint *entrypointBlock `yaml:"entrypoint,omitempty"`
	AIFilename string           `yaml:"aiFilename,omitempty"`
	Resources  *Resources       `yaml:"resources,omitempty"`
	// LegacyPersistence holds the v1 `persistence:` field that lived inside
	// the (then-)agent block. PR #37 deleted it (declared but never
	// consumed) and flipped on strict decoding in the same commit, turning
	// the silent no-op into a hard error for any kit that still had it.
	// normalizeSandbox drops it with a deprecation warning. Drop in the
	// Phase 6 schema-cutover commit alongside LegacyAgent.
	LegacyPersistence string `yaml:"persistence,omitempty"`
}

// entrypointBlock describes the agent's process launch configuration.
type entrypointBlock struct {
	Run      []string `yaml:"run,omitempty"`
	Args     []string `yaml:"args,omitempty"`
	TtyArgs  []string `yaml:"ttyArgs,omitempty"`
	PipeMode string   `yaml:"pipeMode,omitempty"`
}
