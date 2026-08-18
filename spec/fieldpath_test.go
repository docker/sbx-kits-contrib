package spec

import (
	"reflect"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestFieldPaths pins every v1Field / v2Field chain used in this package to
// the YAML path it must produce.
//
// This is the drift alarm the helpers exist for. v1Field/v2Field resolve
// lazily — each call sits inside a normalize branch that only runs for specs
// exercising that legacy surface — so without this test a renamed field or a
// changed yaml tag could ship and only surface as a panic on some user's kit.
// Here, the same rename breaks the build (unknown Go field) or this test (a
// changed tag), whichever applies.
//
// The expected values are the grammar as documented in spec/SPEC-v2.md and
// skills/kit-author/topics/v1-migration.md. Update them only alongside a
// deliberate, documented grammar change.
func TestFieldPaths(t *testing.T) {
	t.Run("v2", func(t *testing.T) {
		for _, tc := range []struct {
			want  string
			names []string
		}{
			{"permissions", []string{"Permissions"}},
			{"permissions.network.allow", []string{"Permissions", "Network", "Allow"}},
			{"permissions.network.deny", []string{"Permissions", "Network", "Deny"}},
			{"agentInstructions.content", []string{"AgentInstructions", "Content"}},
			{"sandbox", []string{"Sandbox"}},
			{"setup.files", []string{"Setup", "Files"}},
			{"setup.startup", []string{"Setup", "Startup"}},
			{"ports", []string{"PublishedPorts"}},
			{"volumes", []string{"Volumes"}},
			{"credentials", []string{"Credentials"}},
			{"credentials[].apiKey", []string{"Credentials", "ApiKey"}},
			{"credentials[].apiKey.name", []string{"Credentials", "ApiKey", "Name"}},
			{"credentials[].apiKey.proxyManaged", []string{"Credentials", "ApiKey", "ProxyManaged"}},
			{"credentials[].apiKey.inject[].domain", []string{"Credentials", "ApiKey", "Inject", "Domain"}},
			{"credentials[].apiKey.inject[].header", []string{"Credentials", "ApiKey", "Inject", "Header"}},
			{"credentials[].apiKey.inject[].format", []string{"Credentials", "ApiKey", "Inject", "Format"}},
			{"credentials[].oauth", []string{"Credentials", "OAuth"}},
		} {
			require.Equal(t, tc.want, v2Field(tc.names...), "v2Field(%v)", tc.names)
		}
	})

	t.Run("v1", func(t *testing.T) {
		for _, tc := range []struct {
			want  string
			names []string
		}{
			{"kind", []string{"Kind"}},
			{"agent", []string{"LegacyAgent"}},
			{"memory", []string{"LegacyMemory"}},
			{"agentContext", []string{"AgentContext"}},
			{"settings", []string{"LegacySettings"}},
			{"persistence", []string{"LegacyPersistence"}},
			{"kitDir", []string{"LegacyKitDir"}},
			{"tmpfs", []string{"LegacyTmpfs"}},
			{"caps", []string{"Caps"}},
			{"oauth", []string{"LegacyOAuth"}},
			{"commands.initFiles", []string{"Commands", "InitFiles"}},
			{"commands.startup", []string{"Commands", "Startup"}},
			{"sandbox.image", []string{"Sandbox", "Image"}},
			{"sandbox.build", []string{"Sandbox", "Build"}},
			{"sandbox.persistence", []string{"Sandbox", "LegacyPersistence"}},
			{"network.allowedDomains", []string{"LegacyNetwork", "AllowedDomains"}},
			{"network.deniedDomains", []string{"LegacyNetwork", "DeniedDomains"}},
			{"network.publishedPorts", []string{"LegacyNetwork", "PublishedPorts"}},
			{"network.serviceAuth", []string{"LegacyNetwork", "ServiceAuth"}},
			{"network.serviceDomains", []string{"LegacyNetwork", "ServiceDomains"}},
			{"environment.proxyManaged", []string{"Environment", "ProxyManaged"}},
		} {
			require.Equal(t, tc.want, v1Field(tc.names...), "v1Field(%v)", tc.names)
		}
	})

	// A collection is only suffixed when the chain continues into an element:
	// "credentials[].apiKey" indexes, a trailing "ports" does not.
	t.Run("collection_suffix_only_when_traversed", func(t *testing.T) {
		require.Equal(t, "ports", v2Field("PublishedPorts"))
		require.Equal(t, "credentials", v2Field("Credentials"))
		require.Equal(t, "credentials[].service", v2Field("Credentials", "Service"))
	})

	// Chains may pass through a map's element type, matching the "[]" suffix
	// emitted for maps.
	t.Run("descends_through_map_element", func(t *testing.T) {
		require.Equal(t, "network.serviceAuth[].headerName",
			v1Field("LegacyNetwork", "ServiceAuth", "HeaderName"))
	})

	t.Run("panics", func(t *testing.T) {
		require.PanicsWithValue(t,
			`spec: fieldPath: type spec.specFileV2 has no field "Nope" (chain [Nope])`,
			func() { v2Field("Nope") })

		// Descending past a scalar must give our targeted message, not
		// reflect's opaque "FieldByName of non-struct type".
		require.PanicsWithValue(t,
			`spec: fieldPath: cannot descend into string to reach "Nope" (chain [Kind Nope])`,
			func() { v1Field("Kind", "Nope") })

		// Manifest.Volumes is yaml:"-" (the volumesField wrapper owns the
		// decode), so it has no addressable YAML path.
		require.Panics(t, func() { fieldPath(reflect.TypeOf(Manifest{}), "Volumes") })
	})
}

func TestSplitLeaf(t *testing.T) {
	prefix, leaf := splitLeaf("credentials[].apiKey.inject[].header")
	require.Equal(t, "credentials[].apiKey.inject[]", prefix)
	require.Equal(t, "header", leaf)

	prefix, leaf = splitLeaf("ports")
	require.Empty(t, prefix)
	require.Equal(t, "ports", leaf)
}
