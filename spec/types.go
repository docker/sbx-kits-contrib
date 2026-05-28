// Package spec defines the declarative kit artifact format for Docker Sandboxes.
// Kit artifacts are directories containing a spec.yaml configuration file and an
// optional files/ directory with static files to inject into containers.
//
// This package provides types, loading, normalization, and validation for spec.yaml
// files. It is designed to be imported by both the public TCK (testcontainers-go
// based) and the internal sandboxes engine.
package spec

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

	// Security defines container security settings.
	Security *Security `json:"security,omitempty" yaml:"security,omitempty"`

	// Volumes are block-volume mounts in dash-style list form. Entries are
	// applied by Path.
	Volumes []MountSpec `json:"volumes,omitempty" yaml:"volumes,omitempty"`

	// Tmpfs are tmpfs mounts in dash-style list form. Entries are applied
	// by Path.
	Tmpfs []MountSpec `json:"tmpfs,omitempty" yaml:"tmpfs,omitempty"`
}

// Security defines container security settings for the sandbox.
type Security struct {
	// Privileged runs the container in privileged mode.
	Privileged bool `json:"privileged,omitempty" yaml:"privileged,omitempty"`
}

// MountSpec is a single mount entry shared by Manifest.Volumes (persistent
// block volumes) and Manifest.Tmpfs (in-memory tmpfs). The fields are
// identical; the semantic distinction lives on the field that holds the
// slice, not on the entry type.
type MountSpec struct {
	// Path is the absolute mount path in the container.
	Path string `json:"path" yaml:"path"`

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

	// PublishedPorts is a list of in-container ports the kit wants the
	// sandbox runtime to expose on the host so external tooling can reach
	// services the kit runs inside the sandbox (a git-daemon, code-server,
	// a Jupyter kernel, …). Each entry is published to an ephemeral host
	// port on 127.0.0.1 when the sandbox starts; the binding is released
	// automatically when the sandbox is deleted.
	//
	// Users who want a fixed host port keep using `sbx ports --publish`
	// on top of the kit's declaration — this field is for the
	// "publish-on-start" UX, not for pinning a specific host port.
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

// CredentialPolicy defines how the agent discovers and uses credentials from the host.
type CredentialPolicy struct {
	// Sources maps service identifiers to credential source definitions.
	Sources map[string]CredentialSource `json:"sources,omitempty" yaml:"sources,omitempty"`
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

// EnvironmentPolicy defines environment variables to set in the container.
type EnvironmentPolicy struct {
	// Variables are static environment variables to set in the container.
	Variables map[string]string `json:"variables,omitempty" yaml:"variables,omitempty"`

	// ProxyManaged lists environment variable names managed by the proxy.
	ProxyManaged []string `json:"proxyManaged,omitempty" yaml:"proxyManaged,omitempty"`
}

// SettingsPolicy defines container settings that control agent-specific
// configuration file creation.
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

	// Content holds the raw file bytes.
	Content []byte `json:"content"`

	// Size is the file size in bytes.
	Size int64 `json:"size"`
}

// Artifact represents a fully loaded and validated kit artifact.
type Artifact struct {
	// Manifest is the required agent/plugin identity and metadata.
	Manifest Manifest `json:"manifest"`

	// Extends is the optional parent kit name for single-parent inheritance.
	Extends string `json:"extends,omitempty"`

	// Locked lists dotted YAML paths (e.g. "agent.image") on this artifact
	// that child kits must not override during single-parent inheritance.
	// The spec library only validates well-formedness; enforcement lives
	// in the consumer that performs the merge.
	Locked []string `json:"locked,omitempty"`

	// Network is the optional network policy.
	Network *NetworkPolicy `json:"network,omitempty"`

	// Credentials is the optional credential policy.
	Credentials *CredentialPolicy `json:"credentials,omitempty"`

	// Environment is the optional environment policy.
	Environment *EnvironmentPolicy `json:"environment,omitempty"`

	// Settings is the optional container settings.
	Settings *SettingsPolicy `json:"settings,omitempty"`

	// Commands is the optional startup commands and init files.
	Commands *CommandsPolicy `json:"commands,omitempty"`

	// OAuth is the optional OAuth configuration.
	OAuth *OAuthPolicy `json:"oauth,omitempty"`

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

// OAuthPolicy defines OAuth configuration for agents that use OAuth-based
// authentication through the proxy.
type OAuthPolicy struct {
	Service             string              `json:"service" yaml:"service"`
	TokenEndpoint       OAuthTokenEndpoint  `json:"tokenEndpoint" yaml:"tokenEndpoint"`
	Sentinels           OAuthSentinels      `json:"sentinels" yaml:"sentinels"`
	CredentialFile      *OAuthCredentialFile `json:"credentialFile,omitempty" yaml:"credentialFile,omitempty"`
	SkipIfEnv           []string            `json:"skipIfEnv,omitempty" yaml:"skipIfEnv,omitempty"`
	ResponseFields      *OAuthResponseFields `json:"responseFields,omitempty" yaml:"responseFields,omitempty"`
	PassthroughResponse bool                `json:"passthroughResponse,omitempty" yaml:"passthroughResponse,omitempty"`
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
type OAuthCredentialFile struct {
	Path     string `json:"path" yaml:"path"`
	Template string `json:"template" yaml:"template"`
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

// specFile is the on-disk YAML schema for spec.yaml.
type specFile struct {
	Manifest    `yaml:",inline"`
	Extends     string             `yaml:"extends,omitempty"`
	Locked      []string           `yaml:"locked,omitempty"`
	Sandbox *sandboxBlock `yaml:"sandbox,omitempty"`
	// LegacyAgent holds the v1 `agent:` block. The normalize step
	// migrates its contents to Sandbox with a deprecation warning. Drop
	// in the Phase 4 schema-cutover commit.
	LegacyAgent *sandboxBlock `yaml:"agent,omitempty"`
	Secrets     []string           `yaml:"secrets,omitempty"`
	Egress      map[string]string  `yaml:"egress,omitempty"`
	Network     *NetworkPolicy     `yaml:"network,omitempty"`
	Credentials *CredentialPolicy  `yaml:"credentials,omitempty"`
	Environment *EnvironmentPolicy `yaml:"environment,omitempty"`
	Settings    *SettingsPolicy    `yaml:"settings,omitempty"`
	Commands    *CommandsPolicy    `yaml:"commands,omitempty"`
	OAuth       *OAuthPolicy       `yaml:"oauth,omitempty"`
	AgentContext string            `yaml:"agentContext,omitempty"`
	// LegacyMemory holds the v1 `memory:` field. The normalize step
	// migrates it to AgentContext with a deprecation warning. Drop in
	// the Phase 4 schema-cutover commit.
	LegacyMemory string            `yaml:"memory,omitempty"`
}

// sandboxBlock groups sandbox-specific configuration (formerly the
// `agent:` block in v1). The Go type was renamed alongside the YAML
// field rename to keep call sites legible.
type sandboxBlock struct {
	Image      string           `yaml:"image,omitempty"`
	Entrypoint *entrypointBlock `yaml:"entrypoint,omitempty"`
	AIFilename string           `yaml:"aiFilename,omitempty"`
	Resources  *Resources       `yaml:"resources,omitempty"`
}

// entrypointBlock describes the agent's process launch configuration.
type entrypointBlock struct {
	Run      []string `yaml:"run,omitempty"`
	Args     []string `yaml:"args,omitempty"`
	TtyArgs  []string `yaml:"ttyArgs,omitempty"`
	PipeMode string   `yaml:"pipeMode,omitempty"`
}
