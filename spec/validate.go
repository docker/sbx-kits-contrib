package spec

import (
	"fmt"
	"maps"
	"path"
	"regexp"
	"slices"
	"strings"

	"github.com/docker/go-units"
)

// namePattern matches valid kit names: lowercase alphanumeric with hyphens,
// must start and end with alphanumeric, 1-64 characters.
var namePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$`)

// aiFilenamePattern restricts the AI profile name to one portable path component.
var aiFilenamePattern = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// shellIdentifierPattern matches valid shell variable names.
var shellIdentifierPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// lockedPathPattern matches a dotted YAML path: lowercase letter or digit
// start, then segments of letters/digits separated by single dots, e.g.
// "sandbox.image" or "permissions.network.allow". Used only for
// well-formedness; the consumer that performs the merge decides which paths
// are meaningful.
var lockedPathPattern = regexp.MustCompile(`^[a-z][a-zA-Z0-9]*(\.[a-z][a-zA-Z0-9]*)*$`)

// octalModePattern matches file mode strings: 3 or 4 octal digits, with an
// optional leading "0". Accepts "755", "0755", "1777", "01777".
var octalModePattern = regexp.MustCompile(`^0?[0-7]{3,4}$`)

// argNamePattern matches a kit-argument name. Hyphens are admitted because
// authors reach for them in multi-word names; a dot is not, so a name can
// never be confused with the dotted ${{ kit.args.<name> }} reference that
// selects it.
var argNamePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*$`)

// ValidateManifest validates a Manifest for correctness. A sandbox kit must
// declare a template (image source); use validateManifest with inheritsImage
// when the artifact supplies its image through the extends chain instead.
func ValidateManifest(m *Manifest) error {
	return validateManifest(m, false)
}

// validateManifest is the extends-aware core. When inheritsImage is true the
// template-required check for sandbox kinds is skipped, because the artifact
// resolves its image from its extends parent rather than declaring one.
func validateManifest(m *Manifest, inheritsImage bool) error {
	if m.SchemaVersion == "" {
		return fmt.Errorf("manifest: schemaVersion is required")
	}
	if !slices.Contains(SupportedSchemaVersions, m.SchemaVersion) {
		return fmt.Errorf("manifest: unsupported schemaVersion %q (supported: %v)", m.SchemaVersion, SupportedSchemaVersions)
	}

	if m.Kind == "" {
		return fmt.Errorf("manifest: kind is required")
	}
	// KindAgent is the v1 alias for KindSandbox and is still accepted at
	// validation time (the normalize step migrates it to KindSandbox with
	// a deprecation warning before this code runs in the load path).
	if m.Kind != KindSandbox && m.Kind != KindAgent && m.Kind != KindMixin {
		return fmt.Errorf("manifest: invalid kind %q (must be %q or %q)", m.Kind, KindSandbox, KindMixin)
	}

	if m.Name == "" {
		return fmt.Errorf("manifest: name is required")
	}
	if !namePattern.MatchString(m.Name) {
		return fmt.Errorf("manifest: invalid name %q (must be lowercase alphanumeric with hyphens, 1-64 chars)", m.Name)
	}

	if m.AIFilename != "" && (m.AIFilename == "." || m.AIFilename == ".." || !aiFilenamePattern.MatchString(m.AIFilename)) {
		return fmt.Errorf("manifest: invalid aiFilename %q (must be a filename containing only letters, numbers, dots, underscores, or hyphens)", m.AIFilename)
	}

	if (m.Kind == KindSandbox || m.Kind == KindAgent) && !inheritsImage {
		if m.Template == "" {
			return fmt.Errorf("manifest: template is required for kind %q", KindSandbox)
		}
	}

	if m.Resources != nil {
		if m.Resources.CPU < 0 {
			return fmt.Errorf("manifest: resources.cpu must be non-negative (got %v)", m.Resources.CPU)
		}
		if m.Resources.MemoryMB < 0 {
			return fmt.Errorf("manifest: resources.memoryMB must be non-negative (got %d)", m.Resources.MemoryMB)
		}
	}

	return nil
}

// ValidateNetworkPolicy validates a NetworkPolicy for correctness.
func ValidateNetworkPolicy(n *NetworkPolicy) error {
	if n == nil {
		return nil
	}

	for service := range n.ServiceAuth {
		auth := n.ServiceAuth[service]
		if auth.HeaderName == "" {
			return fmt.Errorf("network: serviceAuth[%q].headerName is required", service)
		}
		if auth.ValueFormat == "" {
			return fmt.Errorf("network: serviceAuth[%q].valueFormat is required", service)
		}
		if !strings.Contains(auth.ValueFormat, "%s") {
			return fmt.Errorf("network: serviceAuth[%q].valueFormat must contain %%s placeholder", service)
		}
	}

	if len(n.AllowedDomains) > 0 && len(n.DeniedDomains) > 0 {
		allowed := make(map[string]bool, len(n.AllowedDomains))
		for _, d := range n.AllowedDomains {
			allowed[d] = true
		}
		for _, d := range n.DeniedDomains {
			if allowed[d] {
				return fmt.Errorf("network: domain %q is in both allowedDomains and deniedDomains", d)
			}
		}
	}

	return nil
}

// ValidatePublishedPorts validates the canonical top-level publishedPorts
// list: each entry's container port must be in 1..65535 and its protocol must
// be empty (defaulted to "tcp" at consumption time), "tcp", or "udp".
func ValidatePublishedPorts(ports []PublishedPort) error {
	for i, p := range ports {
		if p.Container < 1 || p.Container > 65535 {
			return fmt.Errorf("publishedPorts[%d].container must be in 1..65535 (got %d)", i, p.Container)
		}
		switch p.Protocol {
		case "", "tcp", "udp":
			// "" is accepted and defaults to "tcp" at consumption time.
		default:
			return fmt.Errorf("publishedPorts[%d].protocol must be empty, \"tcp\" or \"udp\" (got %q)", i, p.Protocol)
		}
	}

	return nil
}

// ValidateCredentialPolicy validates a CredentialPolicy for correctness.
func ValidateCredentialPolicy(c *CredentialPolicy) error {
	if c == nil {
		return nil
	}

	for service, source := range c.Sources {
		if len(source.Env) == 0 && source.File == nil {
			return fmt.Errorf("credentials: sources[%q] must have at least one of env or file", service)
		}

		if source.File != nil {
			if source.File.Path == "" {
				return fmt.Errorf("credentials: sources[%q].file.path is required", service)
			}
		}

		if source.Priority != "" && source.Priority != "env-first" && source.Priority != "file-first" {
			return fmt.Errorf("credentials: sources[%q].priority must be \"env-first\" or \"file-first\"", service)
		}
	}

	return nil
}

// ValidateEnvironmentPolicy validates an EnvironmentPolicy for correctness.
func ValidateEnvironmentPolicy(e *EnvironmentPolicy) error {
	if e == nil {
		return nil
	}

	for key := range e.Variables {
		if key == "" {
			return fmt.Errorf("environment: variable key cannot be empty")
		}
		if !shellIdentifierPattern.MatchString(key) {
			return fmt.Errorf("environment: variable key %q is not a valid shell identifier", key)
		}
	}

	for _, key := range e.ProxyManaged {
		if key == "" {
			return fmt.Errorf("environment: proxyManaged entry cannot be empty")
		}
		if !shellIdentifierPattern.MatchString(key) {
			return fmt.Errorf("environment: proxyManaged entry %q is not a valid shell identifier", key)
		}
	}

	return nil
}

// ValidateCommandsPolicy validates a CommandsPolicy for correctness.
func ValidateCommandsPolicy(c *CommandsPolicy) error {
	if c == nil {
		return nil
	}

	for i, cmd := range c.Install {
		if cmd.Command == "" {
			return fmt.Errorf("commands: install[%d].command is required", i)
		}
	}

	for i, cmd := range c.Startup {
		if len(cmd.Command) == 0 {
			return fmt.Errorf("commands: startup[%d].command is required", i)
		}
	}

	for i, f := range c.InitFiles {
		if f.Path == "" {
			return fmt.Errorf("commands: initFiles[%d].path is required", i)
		}
		if !strings.HasPrefix(f.Path, "/") {
			return fmt.Errorf("commands: initFiles[%d].path must be absolute (got %q)", i, f.Path)
		}
		if f.Mode != "" && !octalModePattern.MatchString(f.Mode) {
			return fmt.Errorf("commands: initFiles[%d].mode must be octal (e.g. \"0755\"), got %q", i, f.Mode)
		}
	}

	return nil
}

// ValidateSecurity validates a Security configuration for correctness.
func ValidateSecurity(_ *Security) error {
	return nil
}

// ValidateVolumes validates Manifest.Volumes mount entries. Each entry's
// Type selects the backing storage (MountTypeBlock — encoded as "" — for
// block-backed, MountTypeTmpfs for RAM-backed); any other value is rejected.
func ValidateVolumes(volumes []MountSpec) error {
	for i, m := range volumes {
		if m.Type != MountTypeBlock && m.Type != MountTypeTmpfs {
			return fmt.Errorf("manifest: volumes[%d].type %q is invalid (must be omitted or %q)", i, m.Type, MountTypeTmpfs)
		}
		if m.Path == "" {
			return fmt.Errorf("manifest: volumes[%d].path must not be empty", i)
		}
		if !strings.HasPrefix(m.Path, "/") {
			return fmt.Errorf("manifest: volumes[%d].path %q must be an absolute path", i, m.Path)
		}
		if m.Size != "" {
			if _, err := units.RAMInBytes(m.Size); err != nil {
				return fmt.Errorf("manifest: volumes[%d].size %q is not a valid size: %w", i, m.Size, err)
			}
		}
		if m.Mode != "" && !octalModePattern.MatchString(m.Mode) {
			return fmt.Errorf("manifest: volumes[%d].mode %q must be octal (e.g. \"1777\")", i, m.Mode)
		}
	}
	return nil
}

// ValidateArtifact validates a complete Artifact for internal consistency.
func ValidateArtifact(a *Artifact) error {
	// A sandbox kit that extends a parent inherits its image, so the leaf
	// need not declare a template of its own; the image requirement is
	// satisfied once the extends chain is resolved.
	if err := validateManifest(&a.Manifest, a.Extends != ""); err != nil {
		return err
	}
	if err := ValidateSecurity(a.Manifest.Security); err != nil {
		return err
	}
	if err := ValidateVolumes(a.Manifest.Volumes); err != nil {
		return err
	}
	if err := ValidateRequires(a.Requires); err != nil {
		return err
	}
	// Base-agent affinity only means something for a mixin (which is layered
	// onto a base agent). On a kind: sandbox — which IS a base agent — it is
	// silently ignored at composition time, so reject it here rather than let
	// an author believe it is enforced.
	if a.Requires != nil && a.Requires.Agent != "" && a.Manifest.Kind != KindMixin {
		return fmt.Errorf("requires.agent is only valid for kind %q, not %q — base-agent affinity applies to a mixin layered onto an agent", KindMixin, a.Manifest.Kind)
	}
	// kit-spec v2 forbids a mixin from using extends: mixins are minimally
	// scoped, base-agnostic additions layered onto a base agent, not
	// single-parent-inheriting kits. To derive from a parent agent, use a
	// kind: sandbox kit with extends. Gated on schemaVersion "2" so v1 kits
	// authored before the rule keep validating — the check is additive, never
	// invalidating a previously-accepted v1 spec.
	if a.Manifest.SchemaVersion == "2" && a.Manifest.Kind == KindMixin && a.Extends != "" {
		return fmt.Errorf("kind %q must not set extends (kit-spec v2): mixins are base-agnostic additions; use a kind %q kit with extends to derive from a parent agent", KindMixin, KindSandbox)
	}
	if err := ValidateLocked(a.Locked); err != nil {
		return err
	}
	if err := ValidateLicenses(a.Licenses); err != nil {
		return err
	}
	if err := ValidateArgs(a.Args); err != nil {
		return err
	}
	if err := ValidatePublishedPorts(a.PublishedPorts); err != nil {
		return err
	}
	if err := ValidateEnvironmentPolicy(a.Environment); err != nil {
		return err
	}
	if err := ValidateCommandsPolicy(a.Commands); err != nil {
		return err
	}
	for i, c := range a.Credentials {
		// SPEC-v2 §5.4 makes service REQUIRED on every credential entry: it is
		// the identity the user-side bindings file matches on. For OAuth it
		// carries what v2 moved off the OAuth block onto the parent
		// Credential, and both engine entry points reject an empty one at
		// runtime (the proxy's NewOAuthInterceptorFromConfig, and the
		// configure hook's "oauth service name cannot be empty").
		//
		// §5.4 also specifies a lowercase-kebab charset. That is deliberately
		// NOT enforced: the v1 fold synthesizes service keys from env-var
		// names via deriveServiceKey, which keeps underscores for any
		// multi-word variable (SAMPLE_PROXY_TOKEN -> "sample_proxy"), so
		// enforcing the pattern would reject v1 kits that load today.
		if c.Service == "" {
			return fmt.Errorf("artifact: credentials[%d]: service is required", i)
		}
		if err := ValidateOAuth(c.OAuth); err != nil {
			return fmt.Errorf("artifact: credentials[%d] (service %q): %w", i, c.Service, err)
		}
	}

	for i, f := range a.Files {
		if f.Target != TargetHome && f.Target != TargetWorkspace {
			return fmt.Errorf("artifact: files[%d] has invalid target %q (must be %q or %q)", i, f.Target, TargetHome, TargetWorkspace)
		}
		if f.RelativePath == "" {
			return fmt.Errorf("artifact: files[%d] has empty relativePath", i)
		}
		if strings.HasPrefix(f.RelativePath, "/") || strings.HasPrefix(f.RelativePath, "\\") {
			return fmt.Errorf("artifact: files[%d] relativePath %q must not be absolute", i, f.RelativePath)
		}
		cleaned := path.Clean(f.RelativePath)
		if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
			return fmt.Errorf("artifact: files[%d] relativePath %q escapes the target directory", i, f.RelativePath)
		}
	}

	return nil
}

// ValidateRequires validates the well-formedness of a kit's composition
// preconditions. When set, requires.agent must be a valid kit name (the same
// charset as a Manifest.Name). Whether a given base agent actually satisfies
// the affinity is decided by the consumer that performs composition. A nil
// block, or an empty agent, is valid (no affinity declared).
func ValidateRequires(r *Requires) error {
	if r == nil || r.Agent == "" {
		return nil
	}
	if !namePattern.MatchString(r.Agent) {
		return fmt.Errorf("requires.agent %q is not a valid agent name (must be lowercase alphanumeric with hyphens, 1-64 chars)", r.Agent)
	}
	return nil
}

// ValidateLocked validates the well-formedness of a locked-paths list.
// Each entry must be a non-empty dotted YAML path matching
// lockedPathPattern; duplicates are rejected. Whether a given path is
// meaningful for inheritance is decided by the merge consumer.
func ValidateLocked(paths []string) error {
	seen := make(map[string]struct{}, len(paths))
	for i, p := range paths {
		if p == "" {
			return fmt.Errorf("locked[%d] must not be empty", i)
		}
		if !lockedPathPattern.MatchString(p) {
			return fmt.Errorf("locked[%d] %q is not a well-formed dotted path", i, p)
		}
		if _, dup := seen[p]; dup {
			return fmt.Errorf("locked[%d] %q is duplicated", i, p)
		}
		seen[p] = struct{}{}
	}
	return nil
}

// ValidateLicenses validates the well-formedness of a licenses list (SPDX
// identifiers governing the kit, RFC §280). Each entry must be a non-empty
// string; duplicates are rejected. Per the RFC implementations SHOULD also
// warn on unrecognized SPDX identifiers — that check is deferred (it needs an
// embedded SPDX license list) and would surface as a warning, not an error.
// Composition (union of parent/mixin licenses) is the merge consumer's job.
func ValidateLicenses(licenses []string) error {
	seen := make(map[string]struct{}, len(licenses))
	for i, l := range licenses {
		if l == "" {
			return fmt.Errorf("licenses[%d] must not be empty", i)
		}
		if _, dup := seen[l]; dup {
			return fmt.Errorf("licenses[%d] %q is duplicated", i, l)
		}
		seen[l] = struct{}{}
	}
	return nil
}

// ValidateArgs validates the well-formedness of a kit's argument
// declarations (see KitArg). Each argument declares exactly one of default or
// required: an argument with neither would silently substitute an empty
// string for a value nobody chose, and one with both contradicts itself. A
// declared default must satisfy the argument's own enum or pattern, so an
// author's mistake surfaces at kit validate time rather than at someone
// else's install.
//
// Whether a caller-supplied value satisfies the constraint is checked by the
// consumer that performs the substitution, which necessarily runs before this
// does — placeholders are replaced before the spec can be decoded.
//
// Names are visited in sorted order so a spec with several bad declarations
// always reports the same one.
func ValidateArgs(args map[string]KitArg) error {
	for _, name := range slices.Sorted(maps.Keys(args)) {
		a := args[name]
		if !argNamePattern.MatchString(name) {
			return fmt.Errorf("args[%q] is not a valid argument name (must start with a letter or underscore, followed by letters, digits, underscores, or hyphens)", name)
		}
		switch {
		case a.Default != nil && a.Required:
			return fmt.Errorf("args[%q] declares both a default and required: true; an argument with a default is never required", name)
		case a.Default == nil && !a.Required:
			return fmt.Errorf("args[%q] must declare either a default or required: true", name)
		}
		if len(a.Enum) > 0 && a.Pattern != "" {
			return fmt.Errorf("args[%q] declares both enum and pattern; an exact set of values makes a pattern redundant", name)
		}

		seen := make(map[string]struct{}, len(a.Enum))
		for i, v := range a.Enum {
			if _, dup := seen[v]; dup {
				return fmt.Errorf("args[%q].enum[%d] %q is duplicated", name, i, v)
			}
			seen[v] = struct{}{}
		}
		if a.Pattern != "" {
			if _, err := compileArgPattern(a.Pattern); err != nil {
				return fmt.Errorf("args[%q].pattern is not a valid regexp: %w", name, err)
			}
		}

		if a.Default != nil {
			if err := a.ValidateValue(*a.Default); err != nil {
				return fmt.Errorf("args[%q].default: %w", name, err)
			}
		}
	}
	return nil
}

// ValidateValue reports whether v is an acceptable value for the argument,
// enforcing enum membership or a whole-value pattern match. Consumers call it
// on a caller-supplied value; ValidateArgs applies it to a declared default.
//
// A pattern constrains the whole value: an author writing `[0-9]+` means the
// value is digits, not that it contains digits somewhere.
func (a KitArg) ValidateValue(v string) error {
	if len(a.Enum) > 0 && !slices.Contains(a.Enum, v) {
		quoted := make([]string, len(a.Enum))
		for i, e := range a.Enum {
			quoted[i] = fmt.Sprintf("%q", e)
		}
		return fmt.Errorf("%q is not one of %s", v, strings.Join(quoted, ", "))
	}
	if a.Pattern == "" {
		return nil
	}
	re, err := compileArgPattern(a.Pattern)
	if err != nil {
		return fmt.Errorf("pattern %q is not a valid regexp: %w", a.Pattern, err)
	}
	if !re.MatchString(v) {
		return fmt.Errorf("%q does not match pattern %q", v, a.Pattern)
	}
	return nil
}

// compileArgPattern compiles pat into a whole-value matcher. It compiles pat
// on its own first so a syntax error is reported against what the author
// actually wrote, then wraps it in \A(?:...)\z. Anchoring through the engine
// rather than by inspecting match offsets is what lets an alternation like
// "a|ab" match the whole value instead of settling for its first branch.
// Wrapping is safe precisely because pat already compiled: its groups balance,
// so it cannot escape the wrapper.
func compileArgPattern(pat string) (*regexp.Regexp, error) {
	if _, err := regexp.Compile(pat); err != nil {
		return nil, err
	}
	return regexp.Compile(`\A(?:` + pat + `)\z`)
}

// ValidateOAuthPolicy validates the oauth policy if present.
func ValidateOAuthPolicy(p *OAuthPolicy) error {
	if p == nil {
		return nil
	}
	if p.Service == "" {
		return fmt.Errorf("artifact: oauth: service is required")
	}
	if p.TokenEndpoint.Host == "" {
		return fmt.Errorf("artifact: oauth: tokenEndpoint.host is required")
	}
	if p.TokenEndpoint.Path == "" {
		return fmt.Errorf("artifact: oauth: tokenEndpoint.path is required")
	}
	if p.Sentinels.AccessToken == "" {
		return fmt.Errorf("artifact: oauth: sentinels.accessToken is required")
	}
	if p.Sentinels.RefreshToken == "" {
		return fmt.Errorf("artifact: oauth: sentinels.refreshToken is required")
	}
	if p.CredentialFile != nil {
		if p.CredentialFile.Path == "" {
			return fmt.Errorf("artifact: oauth: credentialFile.path is required")
		}
		if p.CredentialFile.Template == "" && len(p.CredentialFile.Structure) == 0 {
			return fmt.Errorf("artifact: oauth: credentialFile requires either template or structure")
		}
	}
	return nil
}

// ValidateOAuth validates a v2 credentials[].oauth block for structural
// completeness. Same requirements as ValidateOAuthPolicy (its v1
// counterpart), minus Service — that identity lives on the parent
// Credential, not on OAuth itself — and with sentinels not required when
// Passthrough is set: passthrough's whole point is opting out of sentinel
// masking, so an entry that only routes+refreshes a token without ever
// substituting a sentinel for it (e.g. resourceHosts-only OAuth routing)
// legitimately has no sentinels block.
//
// Before this existed, neither of these was caught until much later: a
// missing sentinels block (outside the passthrough case) loads and runs
// with real OAuth tokens never masked in the sandbox, and a credentialFile
// with neither template nor structure loads clean and only fails at first
// `sbx create`, as an opaque engine error with the real cause buried in
// daemon.log rather than at `sbx kit validate` time.
func ValidateOAuth(o *OAuth) error {
	if o == nil {
		return nil
	}
	if o.TokenEndpoint.Host == "" {
		return fmt.Errorf("oauth: tokenEndpoint.host is required")
	}
	if o.TokenEndpoint.Path == "" {
		return fmt.Errorf("oauth: tokenEndpoint.path is required")
	}
	if !o.Passthrough {
		if o.Sentinels.AccessToken == "" {
			return fmt.Errorf("oauth: sentinels.accessToken is required")
		}
		if o.Sentinels.RefreshToken == "" {
			return fmt.Errorf("oauth: sentinels.refreshToken is required")
		}
	}
	if o.CredentialFile != nil {
		if o.CredentialFile.Path == "" {
			return fmt.Errorf("oauth: credentialFile.path is required")
		}
		if o.CredentialFile.Template == "" && len(o.CredentialFile.Structure) == 0 {
			return fmt.Errorf("oauth: credentialFile requires either template or structure")
		}
	}
	return nil
}
