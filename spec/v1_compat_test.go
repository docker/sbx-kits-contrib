package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
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

// TestV2AgentInstructions_PopulatesAgentContext pins the v2 grammar: the
// AI profile content lives under agentInstructions.content (and
// agentInstructions.filename names the file). There is no v1
// memory:/agentContext: surface in a v2 spec.
func TestV2AgentInstructions_PopulatesAgentContext(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: test-agent
sandbox:
  image: example/test:latest
agentInstructions:
  filename: TEST.md
  content: "v2 content"
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}

	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if art.AgentContext != "v2 content" {
		t.Errorf("AgentContext = %q; want v2 content (from agentInstructions.content)", art.AgentContext)
	}
	if art.Manifest.AIFilename != "TEST.md" {
		t.Errorf("AIFilename = %q; want TEST.md (from agentInstructions.filename)", art.Manifest.AIFilename)
	}
	if len(art.Warnings) != 0 {
		t.Errorf("canonical v2 spec must not warn, got %v", art.Warnings)
	}
}

func TestV1Kind_Agent_MapsToSandbox(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
  image: example/test:latest
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Kind != KindSandbox {
		t.Errorf("Kind = %q; want %q (v1 'agent' normalized to v2 'sandbox')", art.Manifest.Kind, KindSandbox)
	}
	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "kind") && strings.Contains(w, "agent") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for kind: agent, got %v", art.Warnings)
	}
}

func TestV2Kind_Sandbox_Accepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: test
sandbox:
  image: example/test:latest
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Kind != KindSandbox {
		t.Errorf("Kind = %q; want %q", art.Manifest.Kind, KindSandbox)
	}
	for _, w := range art.Warnings {
		if strings.Contains(w, "kind") {
			t.Errorf("unexpected deprecation warning for v2 kind: %s", w)
		}
	}
}

func TestV1AgentBlock_MapsToSandbox(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
  image: example/test:latest
  aiFilename: TEST.md
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Template != "example/test:latest" {
		t.Errorf("Template = %q; want example/test:latest", art.Manifest.Template)
	}
	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "agent:") || (strings.Contains(w, "agent") && strings.Contains(w, "sandbox")) {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for agent: block, got %v", art.Warnings)
	}
}

func TestV2SandboxBlock_Accepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: test
sandbox:
  image: example/test:latest
agentInstructions:
  filename: TEST.md
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if art.Manifest.Template != "example/test:latest" {
		t.Errorf("Template = %q; want example/test:latest", art.Manifest.Template)
	}
	if art.Manifest.AIFilename != "TEST.md" {
		t.Errorf("AIFilename = %q; want TEST.md", art.Manifest.AIFilename)
	}
	if len(art.Warnings) != 0 {
		t.Errorf("unexpected warnings for canonical v2 sandbox block: %v", art.Warnings)
	}
}

// TestV1Persistence_Deprecated pins the persistence:-as-deprecation-warning
// shim. The field was a no-op pre-v0.31 (parsed but never consumed); after
// the strict-decode flip in PR #37 it became a hard error with no migration
// path. This shim re-admits it as a deprecation warning, matching the
// pattern established for memory:/kind:agent/agent: block.
func TestV1Persistence_Deprecated(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
  image: example/test:latest
persistence: persistent
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}

	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "persistence") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for persistence, got %v", art.Warnings)
	}
}

// TestV1NestedAgentPersistence_Deprecated is the shape that actually shipped
// in real-world kits — `persistence:` indented under the v1 `agent:` block
// (now `sandboxBlock`). Andre's copilot-dotnet kit reported in
// docker/sbx-releases#191 used this exact form, with the error pointing at
// `spec.agentBlock` rather than the top-level Manifest. The shim folds the
// nested form through normalizeSandbox with a deprecation warning.
func TestV1NestedAgentPersistence_Deprecated(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
  image: example/test:latest
  persistence: persistent
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}

	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "sandbox.persistence") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for sandbox.persistence, got %v", art.Warnings)
	}
}

// TestV1KitDir_Deprecated is the analogue of TestV1Persistence_Deprecated
// for the v1 `kitDir:` field. Same retire-then-strict story; same shim.
func TestV1KitDir_Deprecated(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: agent
name: test
agent:
  image: example/test:latest
kitDir: /opt/whatever
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}

	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "kitDir") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for kitDir, got %v", art.Warnings)
	}
}

func TestVolumesType_TmpfsAccepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: vol-tmpfs
sandbox:
  image: docker/sandbox-templates:shell-docker
volumes:
  - path: /tmp/scratch
    type: tmpfs
    size: 512m
    mode: "1777"
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(art.Manifest.Volumes) != 1 {
		t.Fatalf("expected 1 volume, got %d", len(art.Manifest.Volumes))
	}
	v := art.Manifest.Volumes[0]
	if v.Type != "tmpfs" || v.Path != "/tmp/scratch" || v.Size != "512m" || v.Mode != "1777" {
		t.Errorf("volume mismatch: %#v", v)
	}
}

// TestV1VolumesMap_Deprecated pins the v1 `volumes:` mapping shim.
// Pre-PR #37, `volumes:` was `map[string]string` from container path to
// (sometimes-empty) size string. The polymorphic volumesField wrapper
// accepts this shape and normalize folds it into Manifest.Volumes as
// MountSpec entries with Type left at its zero value (block-backed,
// matching the v1 default), emitting a deprecation warning.
func TestV1VolumesMap_Deprecated(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: legacy-volumes
sandbox:
  image: docker/sandbox-templates:shell-docker
volumes:
  /var/lib/docker: ""
  /opt/data: 4g
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	// Sorted-by-path: /opt/data first, /var/lib/docker second. /var/lib/docker
	// had no size in the v1 spec, so the Size field stays empty.
	if len(art.Manifest.Volumes) != 2 {
		t.Fatalf("expected 2 volumes, got %d", len(art.Manifest.Volumes))
	}
	for i, want := range []MountSpec{
		{Path: "/opt/data", Size: "4g"},
		{Path: "/var/lib/docker"},
	} {
		if art.Manifest.Volumes[i] != want {
			t.Errorf("volume[%d] = %#v; want %#v", i, art.Manifest.Volumes[i], want)
		}
	}

	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "volumes") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for volumes mapping, got %v", art.Warnings)
	}
}

// TestV2VolumesList_Accepted is the negative case for the polymorphic
// wrapper: the v2 sequence shape must continue to round-trip into
// Manifest.Volumes with no deprecation warning, otherwise the wrapper has
// broken the canonical shape that PR #37 introduced.
func TestV2VolumesList_Accepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: v2-volumes
sandbox:
  image: docker/sandbox-templates:shell-docker
volumes:
  - path: /opt/data
    size: 4g
  - path: /var/lib/docker
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(art.Manifest.Volumes) != 2 {
		t.Fatalf("expected 2 volumes, got %d", len(art.Manifest.Volumes))
	}
	if art.Manifest.Volumes[0].Path != "/opt/data" || art.Manifest.Volumes[0].Size != "4g" {
		t.Errorf("volume[0] = %#v; want path=/opt/data size=4g", art.Manifest.Volumes[0])
	}
	for _, w := range art.Warnings {
		if strings.Contains(w, "volumes") {
			t.Errorf("unexpected deprecation warning for v2 volumes list: %s", w)
		}
	}
}

// TestV1TmpfsMap_Deprecated pins the v1 `tmpfs:` mapping shim. Pre-PR #37
// the shape was a mapping from container path to size string (e.g.
// `{ /tmp/scratch: "512m" }`). The decoder now folds it into the canonical
// v2 Volumes list with Type=tmpfs and emits a deprecation warning.
func TestV1TmpfsMap_Deprecated(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: legacy-tmpfs
sandbox:
  image: docker/sandbox-templates:shell-docker
tmpfs:
  /tmp/scratch: 512m
  /var/cache: 256m
`
	if err := os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644); err != nil {
		t.Fatal(err)
	}
	art, err := LoadFromDirectory(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	// Both entries should land on Volumes with Type=tmpfs, sorted by path.
	if len(art.Manifest.Volumes) != 2 {
		t.Fatalf("expected 2 volumes, got %d", len(art.Manifest.Volumes))
	}
	for i, want := range []MountSpec{
		{Path: "/tmp/scratch", Type: MountTypeTmpfs, Size: "512m"},
		{Path: "/var/cache", Type: MountTypeTmpfs, Size: "256m"},
	} {
		if art.Manifest.Volumes[i] != want {
			t.Errorf("volume[%d] = %#v; want %#v", i, art.Manifest.Volumes[i], want)
		}
	}

	foundWarning := false
	for _, w := range art.Warnings {
		if strings.Contains(w, "tmpfs") {
			foundWarning = true
			break
		}
	}
	if !foundWarning {
		t.Errorf("expected deprecation warning for tmpfs, got %v", art.Warnings)
	}
}

// TestV2Credentials_ListShape exercises the minimal shape — one credential
// with apiKey only. Catches "did the new types decode?" regressions
// without obscuring them under a wall of fields.
func TestV2Credentials_ListShape(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: creds-minimal
sandbox:
  image: docker/sandbox-templates:shell-docker
credentials:
  - service: anthropic
    description: "Anthropic API"
    required: true
    apiKey:
      name: ANTHROPIC_API_KEY
      inject:
        - domain: api.anthropic.com
          header: x-api-key
          format: "%s"
`
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644))
	art, err := LoadFromDirectory(dir)
	require.NoError(t, err)
	require.Len(t, art.Credentials, 1)
	c := art.Credentials[0]
	require.Equal(t, "anthropic", c.Service)
	require.True(t, c.Required)
	require.NotNil(t, c.ApiKey)
	require.Equal(t, "ANTHROPIC_API_KEY", c.ApiKey.Name)
	require.Len(t, c.ApiKey.Inject, 1)
	require.Equal(t, "api.anthropic.com", c.ApiKey.Inject[0].Domain)
}

// TestV2Credentials_FullShape exercises every field documented in the
// RFC: apiKey with username (HTTP basic auth for git HTTPS), full oauth
// shape (credentialFile.structure, responseFields, skipIfEnv,
// passthrough+passthroughReason). Schema regressions surface here first.
func TestV2Credentials_FullShape(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: creds-full
sandbox:
  image: docker/sandbox-templates:shell-docker
credentials:
  - service: anthropic
    description: "Anthropic API credentials"
    required: true
    apiKey:
      name: ANTHROPIC_API_KEY
      inject:
        - domain: api.anthropic.com
          header: x-api-key
          format: "%s"
    oauth:
      tokenEndpoint:
        host: platform.claude.com
        path: /v1/oauth/token
      sentinels:
        accessToken: sk-ant-oat01-proxy-managed
        refreshToken: sk-ant-ort01-proxy-managed
      credentialFile:
        path: "~/.claude/.credentials.json"
        structure:
          claudeAiOauth:
            accessToken: "{{.AccessToken}}"
            refreshToken: "{{.RefreshToken}}"
            expiresAt: "{{.ExpiresAt}}"
      responseFields:
        accessToken: access_token
        refreshToken: refresh_token
        expiresIn: expires_in
        scope: scope
      skipIfEnv: [ANTHROPIC_API_KEY]

  - service: github
    description: "GitHub credential for git+API access"
    apiKey:
      name: GITHUB_TOKEN
      inject:
        - domain: api.github.com
          header: Authorization
          format: "Bearer %s"
        - domain: github.com
          header: Authorization
          format: "%s"
          username: x-access-token

  - service: workos
    oauth:
      tokenEndpoint:
        host: api.workos.com
        path: /oauth/token
      sentinels: {}
      passthrough: true
`
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644))
	art, err := LoadFromDirectory(dir)
	require.NoError(t, err)
	require.Len(t, art.Credentials, 3)

	// anthropic — apiKey + full oauth.
	a := art.Credentials[0]
	require.Equal(t, "anthropic", a.Service)
	require.Equal(t, "Anthropic API credentials", a.Description)
	require.True(t, a.Required)
	require.NotNil(t, a.ApiKey)
	require.Equal(t, "ANTHROPIC_API_KEY", a.ApiKey.Name)
	require.NotNil(t, a.OAuth)
	require.Equal(t, "platform.claude.com", a.OAuth.TokenEndpoint.Host)
	require.Equal(t, "/v1/oauth/token", a.OAuth.TokenEndpoint.Path)
	require.Equal(t, "sk-ant-oat01-proxy-managed", a.OAuth.Sentinels.AccessToken)
	require.Equal(t, "sk-ant-ort01-proxy-managed", a.OAuth.Sentinels.RefreshToken)
	require.NotNil(t, a.OAuth.CredentialFile)
	require.Equal(t, "~/.claude/.credentials.json", a.OAuth.CredentialFile.Path)
	require.NotNil(t, a.OAuth.CredentialFile.Structure)
	require.NotNil(t, a.OAuth.ResponseFields)
	require.Equal(t, "access_token", a.OAuth.ResponseFields.AccessToken)
	require.Equal(t, []string{"ANTHROPIC_API_KEY"}, a.OAuth.SkipIfEnv)
	require.False(t, a.OAuth.Passthrough)

	// github — basic auth with username for git HTTPS.
	g := art.Credentials[1]
	require.Equal(t, "github", g.Service)
	require.Len(t, g.ApiKey.Inject, 2)
	require.Equal(t, "x-access-token", g.ApiKey.Inject[1].Username)

	// workos — passthrough OAuth (passthroughReason is deliberately
	// deferred to a later release; this assertion will gain a reason
	// check if/when that field lands).
	w := art.Credentials[2]
	require.True(t, w.OAuth.Passthrough)
}

// TestV1Credentials_FullShape_RoundTripsToList exercises the parallel-load
// contract for the credentials redesign: a realistic v1 spec.yaml using
// credentials.sources + network.serviceAuth + network.serviceDomains +
// environment.proxyManaged loads cleanly, normalizes to a single v2
// credentials[] entry per service, and produces one deprecation warning
// per legacy block touched.
func TestV1Credentials_FullShape_RoundTripsToList(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: creds-v1
sandbox:
  image: docker/sandbox-templates:shell-docker
credentials:
  sources:
    anthropic:
      env: [ANTHROPIC_API_KEY]
      required: true
network:
  serviceDomains:
    api.anthropic.com: anthropic
  serviceAuth:
    anthropic:
      headerName: x-api-key
      valueFormat: "%s"
environment:
  proxyManaged: [ANTHROPIC_API_KEY]
`
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644))
	art, err := LoadFromDirectory(dir)
	require.NoError(t, err)

	// The four v1 surfaces fold into one v2 credentials[] entry.
	require.Len(t, art.Credentials, 1)
	c := art.Credentials[0]
	require.Equal(t, "anthropic", c.Service)
	require.True(t, c.Required)
	require.NotNil(t, c.ApiKey)
	require.Equal(t, "ANTHROPIC_API_KEY", c.ApiKey.Name)
	require.Len(t, c.ApiKey.Inject, 1)
	require.Equal(t, "api.anthropic.com", c.ApiKey.Inject[0].Domain)
	require.Equal(t, "x-api-key", c.ApiKey.Inject[0].Header)
	require.Equal(t, "%s", c.ApiKey.Inject[0].Format)

	// One deprecation warning per legacy block.
	var sourcesWarn, serviceAuthWarn, serviceDomainsWarn, proxyManagedWarn bool
	for _, w := range art.Warnings {
		switch {
		case strings.Contains(w, "credentials.sources"):
			sourcesWarn = true
		case strings.Contains(w, "network.serviceAuth"):
			serviceAuthWarn = true
		case strings.Contains(w, "network.serviceDomains"):
			serviceDomainsWarn = true
		case strings.Contains(w, "environment.proxyManaged"):
			proxyManagedWarn = true
		}
	}
	require.True(t, sourcesWarn, "expected credentials.sources warning, got %v", art.Warnings)
	require.True(t, serviceAuthWarn, "expected network.serviceAuth warning, got %v", art.Warnings)
	require.True(t, serviceDomainsWarn, "expected network.serviceDomains warning, got %v", art.Warnings)
	require.True(t, proxyManagedWarn, "expected environment.proxyManaged warning, got %v", art.Warnings)
}

// TestV1OAuth_StandaloneBlock_RoundTripsToCredentials exercises the
// parallel-load contract for the standalone top-level oauth: block →
// credentials[].oauth migration.
func TestV1OAuth_StandaloneBlock_RoundTripsToCredentials(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: oauth-v1
sandbox:
  image: docker/sandbox-templates:shell-docker
oauth:
  service: openai
  tokenEndpoint: {host: auth.openai.com, path: /oauth/token}
  sentinels: {accessToken: oai-oat01-proxy-managed, refreshToken: oai-ort01-proxy-managed}
`
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644))
	art, err := LoadFromDirectory(dir)
	require.NoError(t, err)

	require.Len(t, art.Credentials, 1)
	c := art.Credentials[0]
	require.Equal(t, "openai", c.Service)
	require.NotNil(t, c.OAuth)
	require.Equal(t, "auth.openai.com", c.OAuth.TokenEndpoint.Host)
	require.Equal(t, "/oauth/token", c.OAuth.TokenEndpoint.Path)

	var oauthWarn bool
	for _, w := range art.Warnings {
		if strings.Contains(w, "oauth:") && strings.Contains(w, "standalone") {
			oauthWarn = true
		}
	}
	require.True(t, oauthWarn, "expected standalone oauth: deprecation warning, got %v", art.Warnings)
}

// TestV2Network_Accepted exercises the v2 permissions.network block —
// allow + deny lists with the three P2 formats (exact, exact:port,
// single-label wildcard).
func TestV2Network_Accepted(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "2"
kind: sandbox
name: net-test
sandbox:
  image: docker/sandbox-templates:shell-docker
permissions:
  network:
    allow: [api.anthropic.com, api.openai.com:443, "*.github.com"]
    deny: [malware.example.com]
`
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644))
	art, err := LoadFromDirectory(dir)
	require.NoError(t, err)
	require.NotNil(t, art.Caps)
	require.NotNil(t, art.Caps.Network)
	require.ElementsMatch(t, []string{"api.anthropic.com", "api.openai.com:443", "*.github.com"}, art.Caps.Network.Allow)
	require.ElementsMatch(t, []string{"malware.example.com"}, art.Caps.Network.Deny)
}

// TestV1NetworkAllowedDomains_RoundTripsToCapsNetwork exercises the
// parallel-load contract for the network -> caps.network rename: a v1
// spec with network.allowedDomains / network.deniedDomains loads
// cleanly, normalizes to caps.network.allow / .deny, and produces one
// deprecation warning per legacy field.
func TestV1NetworkAllowedDomains_RoundTripsToCapsNetwork(t *testing.T) {
	dir := t.TempDir()
	specYAML := `schemaVersion: "1"
kind: sandbox
name: net-v1
sandbox:
  image: docker/sandbox-templates:shell-docker
network:
  allowedDomains: [api.anthropic.com]
  deniedDomains: [malware.example.com]
`
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(specYAML), 0o644))
	art, err := LoadFromDirectory(dir)
	require.NoError(t, err)

	require.NotNil(t, art.Caps)
	require.NotNil(t, art.Caps.Network)
	require.Contains(t, art.Caps.Network.Allow, "api.anthropic.com")
	require.ElementsMatch(t, []string{"malware.example.com"}, art.Caps.Network.Deny)

	var allowWarn, denyWarn bool
	for _, w := range art.Warnings {
		switch {
		case strings.Contains(w, "network.allowedDomains"):
			allowWarn = true
		case strings.Contains(w, "network.deniedDomains"):
			denyWarn = true
		}
	}
	require.True(t, allowWarn, "expected network.allowedDomains warning, got %v", art.Warnings)
	require.True(t, denyWarn, "expected network.deniedDomains warning, got %v", art.Warnings)
}
