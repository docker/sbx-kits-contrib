package spec

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestValidateManifest(t *testing.T) {
	valid := Manifest{
		SchemaVersion: SchemaVersion,
		Kind:          KindMixin,
		Name:          "test-kit",
	}

	t.Run("valid_mixin", func(t *testing.T) {
		require.NoError(t, ValidateManifest(&valid))
	})

	t.Run("valid_agent", func(t *testing.T) {
		m := Manifest{
			SchemaVersion: SchemaVersion,
			Kind:          KindAgent,
			Name:          "test-agent",
			Template:      "docker/sandbox-templates:shell-docker",
		}
		require.NoError(t, ValidateManifest(&m))
	})

	t.Run("missing_schema_version", func(t *testing.T) {
		m := valid
		m.SchemaVersion = ""
		require.ErrorContains(t, ValidateManifest(&m), "schemaVersion")
	})

	t.Run("schema_version_1_accepted", func(t *testing.T) {
		// "1" is the legacy schema version and must keep validating so
		// existing kits in the wild continue to load after the bump.
		m := valid
		m.SchemaVersion = "1"
		require.NoError(t, ValidateManifest(&m))
	})

	t.Run("schema_version_2_accepted", func(t *testing.T) {
		// "2" opts a kit into the v2 OCI distribution format at pack
		// time. The spec library accepts it; downstream tooling reads
		// the value to decide which OCI format to emit.
		m := valid
		m.SchemaVersion = "2"
		require.NoError(t, ValidateManifest(&m))
	})

	t.Run("unsupported_schema_version", func(t *testing.T) {
		// Anything outside SupportedSchemaVersions must hard-fail with a
		// message that names the value seen and the values accepted, so
		// kit authors can spot a typo without grepping the spec library.
		m := valid
		m.SchemaVersion = "99"
		err := ValidateManifest(&m)
		require.ErrorContains(t, err, "unsupported schemaVersion")
		require.ErrorContains(t, err, `"99"`)
	})

	t.Run("missing_kind", func(t *testing.T) {
		m := valid
		m.Kind = ""
		require.ErrorContains(t, ValidateManifest(&m), "kind")
	})

	t.Run("invalid_kind", func(t *testing.T) {
		m := valid
		m.Kind = "banana"
		require.ErrorContains(t, ValidateManifest(&m), "invalid kind")
	})

	t.Run("missing_name", func(t *testing.T) {
		m := valid
		m.Name = ""
		require.ErrorContains(t, ValidateManifest(&m), "name is required")
	})

	t.Run("invalid_name_uppercase", func(t *testing.T) {
		m := valid
		m.Name = "NotLowercase"
		require.ErrorContains(t, ValidateManifest(&m), "invalid name")
	})

	t.Run("valid_ai_filename", func(t *testing.T) {
		for _, name := range []string{"AGENTS.md", "agent_profile-1.md", ".agent.md"} {
			m := valid
			m.AIFilename = name
			require.NoError(t, ValidateManifest(&m))
		}
	})

	for _, tc := range []struct {
		name     string
		filename string
	}{
		{name: "current_directory", filename: "."},
		{name: "parent_directory", filename: ".."},
		{name: "absolute_path", filename: "/tmp/AGENTS.md"},
		{name: "relative_path", filename: "../AGENTS.md"},
		{name: "windows_separator", filename: `dir\AGENTS.md`},
		{name: "shell_metacharacters", filename: "AGENTS.md; touch /tmp/pwned"},
	} {
		t.Run("invalid_ai_filename_"+tc.name, func(t *testing.T) {
			m := valid
			m.AIFilename = tc.filename
			require.ErrorContains(t, ValidateManifest(&m), "invalid aiFilename")
		})
	}

	t.Run("agent_missing_template", func(t *testing.T) {
		m := Manifest{
			SchemaVersion: SchemaVersion,
			Kind:          KindAgent,
			Name:          "test-agent",
		}
		require.ErrorContains(t, ValidateManifest(&m), "template is required")
	})

	t.Run("resources_valid", func(t *testing.T) {
		m := valid
		m.Resources = &Resources{CPU: 2.5, MemoryMB: 4096, GPU: "1"}
		require.NoError(t, ValidateManifest(&m))
	})

	t.Run("resources_negative_cpu", func(t *testing.T) {
		m := valid
		m.Resources = &Resources{CPU: -1}
		require.ErrorContains(t, ValidateManifest(&m), "cpu must be non-negative")
	})

	t.Run("resources_negative_memory", func(t *testing.T) {
		m := valid
		m.Resources = &Resources{MemoryMB: -1}
		require.ErrorContains(t, ValidateManifest(&m), "memoryMB must be non-negative")
	})
}

func TestValidateNetworkPolicy(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateNetworkPolicy(nil))
	})

	t.Run("missing_header_name", func(t *testing.T) {
		n := &NetworkPolicy{
			ServiceAuth: map[string]ServiceAuth{
				"svc": {ValueFormat: "Bearer %s"},
			},
		}
		require.ErrorContains(t, ValidateNetworkPolicy(n), "headerName is required")
	})

	t.Run("missing_value_format_placeholder", func(t *testing.T) {
		n := &NetworkPolicy{
			ServiceAuth: map[string]ServiceAuth{
				"svc": {HeaderName: "Authorization", ValueFormat: "Bearer token"},
			},
		}
		require.ErrorContains(t, ValidateNetworkPolicy(n), "%s placeholder")
	})

	t.Run("allowed_and_denied_disjoint", func(t *testing.T) {
		n := &NetworkPolicy{
			AllowedDomains: []string{"api.example.com:443", "good.example.com:443"},
			DeniedDomains:  []string{"evil.example.com:443"},
		}
		require.NoError(t, ValidateNetworkPolicy(n))
	})

	t.Run("denied_only_is_valid", func(t *testing.T) {
		n := &NetworkPolicy{
			DeniedDomains: []string{"evil.example.com:443"},
		}
		require.NoError(t, ValidateNetworkPolicy(n))
	})

	t.Run("domain_in_both_allow_and_deny", func(t *testing.T) {
		n := &NetworkPolicy{
			AllowedDomains: []string{"api.example.com:443"},
			DeniedDomains:  []string{"api.example.com:443"},
		}
		require.ErrorContains(t, ValidateNetworkPolicy(n), "in both allowedDomains and deniedDomains")
	})

}

func TestValidatePublishedPorts(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidatePublishedPorts(nil))
	})

	t.Run("minimal", func(t *testing.T) {
		// Only Container is required; empty Protocol is accepted (consumers
		// default it to "tcp" at use-site to keep this struct ergonomic).
		require.NoError(t, ValidatePublishedPorts([]PublishedPort{{Container: 8080}}))
	})

	t.Run("full", func(t *testing.T) {
		require.NoError(t, ValidatePublishedPorts([]PublishedPort{
			{Container: 9418, Protocol: "tcp", Name: "git-daemon"},
			{Container: 8080, Protocol: "tcp", Name: "code-server"},
			{Container: 53, Protocol: "udp", Name: "dns"},
		}))
	})

	t.Run("container_out_of_range", func(t *testing.T) {
		for _, p := range []int{0, -1, 65536, 70000} {
			require.ErrorContains(t, ValidatePublishedPorts([]PublishedPort{{Container: p}}),
				"publishedPorts[0].container must be in 1..65535",
				"container=%d", p)
		}
	})

	t.Run("invalid_protocol", func(t *testing.T) {
		require.ErrorContains(t,
			ValidatePublishedPorts([]PublishedPort{{Container: 8080, Protocol: "sctp"}}),
			"publishedPorts[0].protocol must be empty, \"tcp\" or \"udp\"")
	})
}

func TestValidateCredentialPolicy(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateCredentialPolicy(nil))
	})

	t.Run("no_env_or_file", func(t *testing.T) {
		c := &CredentialPolicy{
			Sources: map[string]CredentialSource{
				"svc": {},
			},
		}
		require.ErrorContains(t, ValidateCredentialPolicy(c), "at least one of env or file")
	})

	t.Run("invalid_priority", func(t *testing.T) {
		c := &CredentialPolicy{
			Sources: map[string]CredentialSource{
				"svc": {Env: []string{"KEY"}, Priority: "wrong"},
			},
		}
		require.ErrorContains(t, ValidateCredentialPolicy(c), "priority")
	})
}

func TestValidateEnvironmentPolicy(t *testing.T) {
	t.Run("invalid_variable_key", func(t *testing.T) {
		e := &EnvironmentPolicy{
			Variables: map[string]string{"123-bad": "val"},
		}
		require.ErrorContains(t, ValidateEnvironmentPolicy(e), "not a valid shell identifier")
	})

	t.Run("invalid_proxy_managed", func(t *testing.T) {
		e := &EnvironmentPolicy{
			ProxyManaged: []string{"bad-name"},
		}
		require.ErrorContains(t, ValidateEnvironmentPolicy(e), "not a valid shell identifier")
	})
}

func TestValidateCommandsPolicy(t *testing.T) {
	t.Run("empty_install_command", func(t *testing.T) {
		c := &CommandsPolicy{
			Install: []InstallCommand{{Command: ""}},
		}
		require.ErrorContains(t, ValidateCommandsPolicy(c), "command is required")
	})

	t.Run("relative_initfile_path", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "relative/path", Content: "x"}},
		}
		require.ErrorContains(t, ValidateCommandsPolicy(c), "must be absolute")
	})

	t.Run("non_workdir_dollar_brace_is_not_a_validation_error", func(t *testing.T) {
		// initFiles[].content is opaque file content, most commonly a
		// script. Only "${WORKDIR}" is a kit-spec placeholder (substituted
		// by a literal string replace at kit-load time); any other
		// "${...}" is the consuming shell/interpreter's own syntax and
		// must pass through unexamined.
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "/tmp/f", Content: "${HOME}/data"}},
		}
		require.NoError(t, ValidateCommandsPolicy(c))
	})

	t.Run("supported_placeholder", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "/tmp/f", Content: "${WORKDIR}/data"}},
		}
		require.NoError(t, ValidateCommandsPolicy(c))
	})

	t.Run("bash_parameter_expansions_in_content_are_not_validation_errors", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{
				Path: "/home/agent/test.sh",
				Mode: "0755",
				Content: `#!/bin/bash
NAME="World"
COUNT=4
TOTAL=10
REMAINING=$((TOTAL - COUNT))
printf -v FILL "%${COUNT}s" ""
printf -v PAD  "%${REMAINING}s" ""
BAR="${FILL// /#}${PAD// /-}"
echo "Hello, ${NAME} [${BAR}]"
`,
			}},
		}
		require.NoError(t, ValidateCommandsPolicy(c))
	})

	t.Run("empty_startup_command", func(t *testing.T) {
		c := &CommandsPolicy{
			Startup: []StartupCommand{{Command: nil}},
		}
		require.ErrorContains(t, ValidateCommandsPolicy(c), "command is required")
	})

	t.Run("valid_initfile_mode", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "/tmp/f", Content: "x", Mode: "0644"}},
		}
		require.NoError(t, ValidateCommandsPolicy(c))
	})

	t.Run("invalid_initfile_mode", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "/tmp/f", Content: "x", Mode: "rwx"}},
		}
		require.ErrorContains(t, ValidateCommandsPolicy(c), "must be octal")
	})
}

func TestValidateVolumes(t *testing.T) {
	t.Run("valid", func(t *testing.T) {
		require.NoError(t, ValidateVolumes([]MountSpec{{Path: "/data", Size: "4g", Mode: "0755"}}))
	})

	t.Run("path_only_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateVolumes([]MountSpec{{Path: "/data"}}))
	})

	t.Run("empty_path", func(t *testing.T) {
		require.ErrorContains(t, ValidateVolumes([]MountSpec{{Path: ""}}), "volumes[0].path must not be empty")
	})

	t.Run("relative_path", func(t *testing.T) {
		require.ErrorContains(t, ValidateVolumes([]MountSpec{{Path: "data"}}), "volumes[0].path \"data\" must be an absolute path")
	})

	t.Run("invalid_size", func(t *testing.T) {
		require.ErrorContains(t, ValidateVolumes([]MountSpec{{Path: "/data", Size: "huge"}}), "volumes[0].size \"huge\" is not a valid size")
	})

	t.Run("invalid_mode", func(t *testing.T) {
		require.ErrorContains(t, ValidateVolumes([]MountSpec{{Path: "/data", Mode: "rwx"}}), "volumes[0].mode \"rwx\" must be octal")
	})
}

func TestValidateArtifact_MountSpecType(t *testing.T) {
	base := Manifest{
		SchemaVersion: SchemaVersion,
		Kind:          KindSandbox,
		Name:          "vol-type-test",
		Template:      "docker/sandbox-templates:shell-docker",
	}

	t.Run("empty type accepted", func(t *testing.T) {
		m := base
		m.Volumes = []MountSpec{{Path: "/data"}}
		require.NoError(t, ValidateArtifact(&Artifact{Manifest: m}))
	})
	t.Run("tmpfs type accepted", func(t *testing.T) {
		m := base
		m.Volumes = []MountSpec{{Path: "/tmp/scratch", Type: "tmpfs"}}
		require.NoError(t, ValidateArtifact(&Artifact{Manifest: m}))
	})
	t.Run("invalid type rejected", func(t *testing.T) {
		m := base
		m.Volumes = []MountSpec{{Path: "/data", Type: "bogus"}}
		err := ValidateArtifact(&Artifact{Manifest: m})
		require.ErrorContains(t, err, "type")
		require.ErrorContains(t, err, "bogus")
	})
}

func TestValidateLocked(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateLocked(nil))
	})

	t.Run("simple_paths", func(t *testing.T) {
		require.NoError(t, ValidateLocked([]string{"agent.image", "network.allowedDomains"}))
	})

	t.Run("single_segment_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateLocked([]string{"memory"}))
	})

	t.Run("empty_entry", func(t *testing.T) {
		require.ErrorContains(t, ValidateLocked([]string{""}), "must not be empty")
	})

	t.Run("leading_dot", func(t *testing.T) {
		require.ErrorContains(t, ValidateLocked([]string{".image"}), "not a well-formed dotted path")
	})

	t.Run("trailing_dot", func(t *testing.T) {
		require.ErrorContains(t, ValidateLocked([]string{"agent."}), "not a well-formed dotted path")
	})

	t.Run("double_dot", func(t *testing.T) {
		require.ErrorContains(t, ValidateLocked([]string{"agent..image"}), "not a well-formed dotted path")
	})

	t.Run("disallowed_chars", func(t *testing.T) {
		require.ErrorContains(t, ValidateLocked([]string{"agent.image[0]"}), "not a well-formed dotted path")
	})

	t.Run("duplicate", func(t *testing.T) {
		require.ErrorContains(t, ValidateLocked([]string{"agent.image", "agent.image"}), "duplicated")
	})
}

func TestValidateRequires(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateRequires(nil))
	})

	t.Run("empty_agent_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateRequires(&Requires{}))
	})

	t.Run("valid_agent", func(t *testing.T) {
		require.NoError(t, ValidateRequires(&Requires{Agent: "claude"}))
	})

	t.Run("invalid_name", func(t *testing.T) {
		require.ErrorContains(t, ValidateRequires(&Requires{Agent: "Not A Name"}), "not a valid agent name")
	})
}

func TestValidateLicenses(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateLicenses(nil))
	})

	t.Run("spdx_identifiers", func(t *testing.T) {
		require.NoError(t, ValidateLicenses([]string{"MIT", "Apache-2.0"}))
	})

	t.Run("empty_entry", func(t *testing.T) {
		require.ErrorContains(t, ValidateLicenses([]string{"MIT", ""}), "must not be empty")
	})

	t.Run("duplicate", func(t *testing.T) {
		require.ErrorContains(t, ValidateLicenses([]string{"MIT", "MIT"}), "duplicated")
	})
}

func TestValidateOAuthPolicy(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateOAuthPolicy(nil))
	})

	t.Run("missing_service", func(t *testing.T) {
		require.ErrorContains(t, ValidateOAuthPolicy(&OAuthPolicy{}), "service is required")
	})

	t.Run("missing_token_endpoint_host", func(t *testing.T) {
		p := &OAuthPolicy{Service: "svc", TokenEndpoint: OAuthTokenEndpoint{Path: "/token"}}
		require.ErrorContains(t, ValidateOAuthPolicy(p), "host is required")
	})

	t.Run("missing_token_endpoint_path", func(t *testing.T) {
		p := &OAuthPolicy{Service: "svc", TokenEndpoint: OAuthTokenEndpoint{Host: "auth.example.com"}}
		require.ErrorContains(t, ValidateOAuthPolicy(p), "path is required")
	})

	t.Run("missing_sentinels", func(t *testing.T) {
		p := &OAuthPolicy{
			Service:       "svc",
			TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
		}
		require.ErrorContains(t, ValidateOAuthPolicy(p), "accessToken is required")
	})

	t.Run("valid_full", func(t *testing.T) {
		p := &OAuthPolicy{
			Service:       "svc",
			TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:     OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
		}
		require.NoError(t, ValidateOAuthPolicy(p))
	})

	t.Run("credential_file_missing_path", func(t *testing.T) {
		p := &OAuthPolicy{
			Service:        "svc",
			TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{Template: "tmpl"},
		}
		require.ErrorContains(t, ValidateOAuthPolicy(p), "credentialFile.path is required")
	})

	t.Run("credential_file_missing_template_and_structure", func(t *testing.T) {
		p := &OAuthPolicy{
			Service:        "svc",
			TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{Path: "/cred"},
		}
		require.ErrorContains(t, ValidateOAuthPolicy(p), "credentialFile requires either template or structure")
	})

	t.Run("credential_file_structure_only_valid", func(t *testing.T) {
		p := &OAuthPolicy{
			Service:       "svc",
			TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:     OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{
				Path:      "/cred",
				Structure: map[string]any{"accessToken": "{{.AccessToken}}"},
			},
		}
		require.NoError(t, ValidateOAuthPolicy(p))
	})
}

func TestValidateApiKey(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateApiKey(nil, "2"))
	})

	// An empty name is a legitimate shape (proxy-side-only credential); it is
	// no longer rejected here — ValidateArtifact warns instead, see
	// TestValidateArtifact/apikey_empty_name_warns_not_errors.
	t.Run("v2_missing_name_allowed", func(t *testing.T) {
		a := &ApiKey{Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}}}
		require.NoError(t, ValidateApiKey(a, "2"))
	})

	// v1's serviceDomains+serviceAuth fold can yield a header-only inject
	// with no name that still injects, so schemaVersion "1" must accept it.
	t.Run("v1_missing_name_grandfathered", func(t *testing.T) {
		a := &ApiKey{Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}}}
		require.NoError(t, ValidateApiKey(a, "1"))
	})

	// name is an env-var name; a non-empty malformed one always loads clean
	// today but the value is never actually reachable in-container.
	t.Run("malformed_name_rejected", func(t *testing.T) {
		a := &ApiKey{Name: "bad-name", Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}}}
		require.ErrorContains(t, ValidateApiKey(a, "2"), "not a valid shell identifier")
	})

	t.Run("malformed_name_rejected_v1", func(t *testing.T) {
		a := &ApiKey{Name: "bad-name", Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}}}
		require.ErrorContains(t, ValidateApiKey(a, "1"), "not a valid shell identifier")
	})

	t.Run("valid_underscore_leading_name_accepted", func(t *testing.T) {
		a := &ApiKey{Name: "_OK_NAME2", Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}}}
		require.NoError(t, ValidateApiKey(a, "2"))
	})

	t.Run("v1_empty_name_not_subject_to_shell_identifier_check", func(t *testing.T) {
		a := &ApiKey{Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}}}
		require.NoError(t, ValidateApiKey(a, "1"))
	})

	t.Run("empty_inject_domain_rejected", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Header: "x-api-key", Format: "%s"}}}
		require.ErrorContains(t, ValidateApiKey(a, "2"), "inject[0].domain is required")
	})

	t.Run("format_with_zero_placeholders_rejected", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Header: "h", Format: "static"}}}
		require.ErrorContains(t, ValidateApiKey(a, "2"), "exactly one %s placeholder")
	})

	t.Run("format_with_two_placeholders_rejected", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Header: "h", Format: "%s-%s"}}}
		require.ErrorContains(t, ValidateApiKey(a, "2"), "exactly one %s placeholder")
	})

	// Neither header nor username is a legitimate shape too — it maps the
	// domain to the credential's service without injecting anything; it is
	// no longer rejected here — ValidateArtifact warns instead, see
	// TestValidateArtifact/apikey_inert_inject_warns_not_errors.
	t.Run("inert_inject_allowed", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Format: "%s"}}}
		require.NoError(t, ValidateApiKey(a, "2"))
	})

	t.Run("header_only_valid", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Header: "x-api-key", Format: "%s"}}}
		require.NoError(t, ValidateApiKey(a, "2"))
	})

	// header alone has no template to substitute the credential into, so it
	// never actually injects at runtime — only the username/Basic path can
	// omit format.
	t.Run("header_without_format_rejected", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Header: "x-api-key"}}}
		require.ErrorContains(t, ValidateApiKey(a, "2"), "sets header but no format")
	})

	t.Run("username_only_valid", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Username: "x-access-token"}}}
		require.NoError(t, ValidateApiKey(a, "2"))
	})

	// HTTP Basic (RFC 7617) parses everything after the first colon as the
	// password, so a colon-bearing username can never authenticate as declared.
	t.Run("username_with_colon_rejected", func(t *testing.T) {
		a := &ApiKey{Name: "TOKEN", Inject: []ApiKeyInject{{Domain: "d.example.com", Username: "a:b", Format: "%s"}}}
		require.ErrorContains(t, ValidateApiKey(a, "2"), `username must not contain ":"`)
	})
}

func TestValidateOAuth(t *testing.T) {
	t.Run("nil_is_valid", func(t *testing.T) {
		require.NoError(t, ValidateOAuth(nil))
	})

	t.Run("missing_token_endpoint_host", func(t *testing.T) {
		o := &OAuth{TokenEndpoint: OAuthTokenEndpoint{Path: "/token"}}
		require.ErrorContains(t, ValidateOAuth(o), "host is required")
	})

	t.Run("missing_token_endpoint_path", func(t *testing.T) {
		o := &OAuth{TokenEndpoint: OAuthTokenEndpoint{Host: "auth.example.com"}}
		require.ErrorContains(t, ValidateOAuth(o), "path is required")
	})

	t.Run("missing_sentinels", func(t *testing.T) {
		o := &OAuth{TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"}}
		require.ErrorContains(t, ValidateOAuth(o), "accessToken is required")
	})

	t.Run("valid_full", func(t *testing.T) {
		o := &OAuth{
			TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:     OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
		}
		require.NoError(t, ValidateOAuth(o))
	})

	t.Run("credential_file_missing_path", func(t *testing.T) {
		o := &OAuth{
			TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{Template: "tmpl"},
		}
		require.ErrorContains(t, ValidateOAuth(o), "credentialFile.path is required")
	})

	t.Run("credential_file_missing_template_and_structure", func(t *testing.T) {
		o := &OAuth{
			TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{Path: "/cred"},
		}
		require.ErrorContains(t, ValidateOAuth(o), "credentialFile requires either template or structure")
	})

	t.Run("credential_file_structure_only_valid", func(t *testing.T) {
		o := &OAuth{
			TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{Path: "/cred", Structure: map[string]interface{}{"k": "{{.AccessToken}}"}},
		}
		require.NoError(t, ValidateOAuth(o))
	})

	t.Run("passthrough_does_not_require_sentinels", func(t *testing.T) {
		o := &OAuth{
			TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Passthrough:   true,
		}
		require.NoError(t, ValidateOAuth(o))
	})

	t.Run("passthrough_still_requires_token_endpoint", func(t *testing.T) {
		o := &OAuth{Passthrough: true}
		require.ErrorContains(t, ValidateOAuth(o), "host is required")
	})
}

func TestValidateArtifact(t *testing.T) {
	t.Run("valid_mixin", func(t *testing.T) {
		a := &Artifact{Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"}}
		require.NoError(t, ValidateArtifact(a))
	})

	t.Run("invalid_file_target", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Files:    []ArtifactFile{{RelativePath: "f.txt", Target: "nowhere"}},
		}
		require.ErrorContains(t, ValidateArtifact(a), "invalid target")
	})

	t.Run("absolute_file_path", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Files:    []ArtifactFile{{RelativePath: "/etc/passwd", Target: TargetHome}},
		}
		require.ErrorContains(t, ValidateArtifact(a), "must not be absolute")
	})

	t.Run("path_traversal", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Files:    []ArtifactFile{{RelativePath: "../escape", Target: TargetHome}},
		}
		require.ErrorContains(t, ValidateArtifact(a), "escapes the target directory")
	})

	t.Run("sandbox_missing_template_without_extends", func(t *testing.T) {
		a := &Artifact{Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindSandbox, Name: "ok"}}
		require.ErrorContains(t, ValidateArtifact(a), "template is required")
	})

	t.Run("sandbox_inherits_template_via_extends", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindSandbox, Name: "ok"},
			Extends:  "claude",
		}
		require.NoError(t, ValidateArtifact(a))
	})

	t.Run("requires_on_mixin_allowed", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Requires: &Requires{Agent: "claude"},
		}
		require.NoError(t, ValidateArtifact(a))
	})

	t.Run("requires_on_sandbox_rejected", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindSandbox, Name: "ok", Template: "img"},
			Requires: &Requires{Agent: "claude"},
		}
		require.ErrorContains(t, ValidateArtifact(a), "requires.agent is only valid for kind")
	})

	t.Run("v2_mixin_with_extends_rejected", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Extends:  "claude",
		}
		require.ErrorContains(t, ValidateArtifact(a), "must not set extends")
	})

	t.Run("v1_mixin_with_extends_grandfathered", func(t *testing.T) {
		// Backwards compatibility: the v2 rule must not invalidate a v1 kit
		// that predates it.
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "1", Kind: KindMixin, Name: "ok"},
			Extends:  "claude",
		}
		require.NoError(t, ValidateArtifact(a))
	})

	t.Run("v2_sandbox_with_extends_allowed", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindSandbox, Name: "ok"},
			Extends:  "claude",
		}
		require.NoError(t, ValidateArtifact(a))
	})

	// Regression coverage for https://github.com/docker/sandboxes/issues/4835:
	// a credentials[].oauth block with neither credentialFile.template nor
	// .structure, or with no sentinels block at all, used to load as VALID
	// and only fail much later — at first `sbx create`, as an opaque engine
	// error, or (for missing sentinels) not at all, silently leaving real
	// OAuth tokens unmasked in the sandbox.
	t.Run("oauth_credential_file_neither_template_nor_structure_rejected", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Credentials: []Credential{{
				Service: "anthropic",
				OAuth: &OAuth{
					TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
					Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
					CredentialFile: &OAuthCredentialFile{Path: "/cred"},
				},
			}},
		}
		err := ValidateArtifact(a)
		require.ErrorContains(t, err, "credentials[0]")
		require.ErrorContains(t, err, `"anthropic"`)
		require.ErrorContains(t, err, "credentialFile requires either template or structure")
	})

	t.Run("oauth_missing_sentinels_rejected", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Credentials: []Credential{{
				Service: "anthropic",
				OAuth:   &OAuth{TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"}},
			}},
		}
		require.ErrorContains(t, ValidateArtifact(a), "accessToken is required")
	})

	// SPEC-v2 §5.4 makes service REQUIRED on every credential entry. For
	// OAuth the engine additionally rejects an empty service at runtime in
	// two places (NewOAuthInterceptorFromConfig, and the configure hook's
	// "oauth service name cannot be empty"), so validate must catch it first.
	t.Run("oauth_without_service_rejected", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Credentials: []Credential{{
				OAuth: &OAuth{
					TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
					Sentinels:     OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
				},
			}},
		}
		require.ErrorContains(t, ValidateArtifact(a), "credentials[0]: service is required")
	})

	t.Run("apikey_without_service_rejected", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Credentials: []Credential{{
				ApiKey: &ApiKey{Name: "SOME_TOKEN"},
			}},
		}
		require.ErrorContains(t, ValidateArtifact(a), "credentials[0]: service is required")
	})

	// The v1 fold derives service keys from env-var names and keeps
	// underscores, so §5.4's lowercase-kebab charset is not enforced on the
	// canonical artifact — such kits must keep loading.
	t.Run("non_kebab_service_accepted", func(t *testing.T) {
		a := &Artifact{
			Manifest:    Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Credentials: []Credential{{Service: "sample_proxy", ApiKey: &ApiKey{Name: "SAMPLE_PROXY_TOKEN"}}},
		}
		require.NoError(t, ValidateArtifact(a))
	})

	// proxyManaged: true copies apiKey.name into the derived
	// Environment.ProxyManaged list; a malformed name must still be
	// attributed to the credential, not to that derived list.
	t.Run("proxymanaged_malformed_name_errors_as_apikey_not_environment", func(t *testing.T) {
		yamlBytes := []byte(`
schemaVersion: "2"
kind: mixin
name: creds-proxy-managed
permissions:
  network:
    allow:
      - api.example.com
credentials:
  - service: svc
    apiKey:
      name: bad-name
      proxyManaged: true
      inject:
        - domain: api.example.com
          header: x-api-key
          format: "%s"
`)
		art, err := LoadArtifactFromBytes(yamlBytes)
		require.NoError(t, err)
		require.Equal(t, []string{"bad-name"}, art.Environment.ProxyManaged,
			"precondition: the name must have propagated to the derived environment list")

		err = ValidateArtifact(art)
		require.ErrorContains(t, err, "apiKey: name")
		require.ErrorContains(t, err, "not a valid shell identifier")
		require.NotContains(t, err.Error(), "environment: proxyManaged",
			"error must be attributed to the credential, not the derived environment list")
	})

	t.Run("apikey_explicit_header_and_format_valid", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.anthropic.com"}}},
			Credentials: []Credential{{
				Service: "anthropic",
				ApiKey: &ApiKey{
					Name:   "ANTHROPIC_API_KEY",
					Inject: []ApiKeyInject{{Domain: "api.anthropic.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings)
	})

	t.Run("apikey_inject_domain_not_allowed_warns_not_errors", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"other.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "svc.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a), "an uncovered inject domain must warn, not fail validation")
		require.True(t, hasWarningContaining(a.Warnings, `credentials[0] (service "svc") inject[0].domain "svc.example.com"`),
			"expected an uncovered-domain warning, got %v", a.Warnings)
	})

	// Coverage warnings are validator-owned: revalidating the same artifact
	// must not accumulate a duplicate per call.
	t.Run("apikey_inject_domain_warning_is_idempotent_across_revalidation", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"other.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "svc.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.NoError(t, ValidateArtifact(a))
		count := 0
		for _, w := range a.Warnings {
			if strings.Contains(w, `credentials[0] (service "svc") inject[0].domain "svc.example.com"`) {
				count++
			}
		}
		require.Equal(t, 1, count, "revalidation must not duplicate the warning, got %v", a.Warnings)
	})

	// Coverage warnings are also self-healing: once the allow list is fixed,
	// revalidating the same artifact must drop the now-stale warning.
	t.Run("apikey_inject_domain_warning_clears_once_allow_list_fixed", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"other.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "svc.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.NotEmpty(t, a.Warnings, "precondition: the domain must start out uncovered")

		a.Caps.Network.Allow = append(a.Caps.Network.Allow, "svc.example.com")
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings, "the warning must clear once the domain is covered, got %v", a.Warnings)
	})

	t.Run("apikey_inject_domain_covered_by_wildcard_no_warning", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"*.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "svc.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings)
	})

	// A port range never matches a request, so it doesn't cover the domain.
	t.Run("apikey_inject_domain_port_range_allow_still_warns", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com:80-443"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.True(t, hasWarningContaining(a.Warnings, `credentials[0] (service "svc") inject[0].domain "api.example.com"`),
			"a port-range allow entry never matches, so it must still warn; got %v", a.Warnings)
	})

	t.Run("apikey_inject_domain_port_wildcard_allow_no_warning", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com:*"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings)
	})

	t.Run("apikey_inject_domain_multilabel_wildcard_allow_no_warning", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"**.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "a.b.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings)
	})

	// An empty apiKey.name on a v2 spec is a legitimate shape — the
	// credential is handled entirely proxy-side — so it must warn, not fail.
	t.Run("apikey_empty_name_warns_not_errors", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a), "an empty apiKey.name must warn, not fail validation")
		require.True(t, hasWarningContaining(a.Warnings, `credentials[0] (service "svc")`),
			"expected an empty-name warning, got %v", a.Warnings)
		// Name alone derives nothing in-container; the remediation must say so.
		require.True(t, hasWarningContaining(a.Warnings, "proxyManaged: true"),
			"remediation must tell the author proxyManaged: true is also required, got %v", a.Warnings)
	})

	t.Run("apikey_empty_name_warning_is_idempotent_across_revalidation", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.NoError(t, ValidateArtifact(a))
		count := 0
		for _, w := range a.Warnings {
			if strings.HasPrefix(w, apiKeyNameEmptyWarningPrefix) {
				count++
			}
		}
		require.Equal(t, 1, count, "revalidation must not duplicate the warning, got %v", a.Warnings)
	})

	// Self-healing: once the author sets a name, revalidating the same
	// artifact must drop the now-stale warning.
	t.Run("apikey_empty_name_warning_clears_once_name_set", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.NotEmpty(t, a.Warnings, "precondition: the name must start out empty")

		a.Credentials[0].ApiKey.Name = "SVC_TOKEN"
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings, "the warning must clear once name is set, got %v", a.Warnings)
	})

	// The v1 serviceDomains+serviceAuth fold can legitimately produce a
	// no-name apiKey; the empty-name warning is v2-only, so a v1 artifact
	// must not receive it either.
	t.Run("apikey_empty_name_not_warned_on_v1", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "1", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Inject: []ApiKeyInject{{Domain: "api.example.com", Header: "x-api-key", Format: "%s"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings)
	})

	// An inject entry with neither header nor username is a legitimate
	// shape — it associates the domain with the credential's service for
	// routing/policy purposes without injecting anything — so it must warn,
	// not fail.
	t.Run("apikey_inert_inject_warns_not_errors", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "api.example.com"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a), "an inert inject must warn, not fail validation")
		require.True(t, hasWarningContaining(a.Warnings, `credentials[0] (service "svc") inject[0].domain "api.example.com"`),
			"expected an inert-inject warning, got %v", a.Warnings)
	})

	t.Run("apikey_inert_inject_warning_is_idempotent_across_revalidation", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "api.example.com"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.NoError(t, ValidateArtifact(a))
		count := 0
		for _, w := range a.Warnings {
			if strings.HasPrefix(w, inertInjectWarningPrefix) {
				count++
			}
		}
		require.Equal(t, 1, count, "revalidation must not duplicate the warning, got %v", a.Warnings)
	})

	// Self-healing: once the author adds a header/format, revalidating the
	// same artifact must drop the now-stale warning.
	t.Run("apikey_inert_inject_warning_clears_once_header_set", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "ok"},
			Caps:     &Caps{Network: &CapsNetwork{Allow: []string{"api.example.com"}}},
			Credentials: []Credential{{
				Service: "svc",
				ApiKey: &ApiKey{
					Name:   "SVC_TOKEN",
					Inject: []ApiKeyInject{{Domain: "api.example.com"}},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
		require.NotEmpty(t, a.Warnings, "precondition: the inject must start out inert")

		a.Credentials[0].ApiKey.Inject[0].Header = "x-api-key"
		a.Credentials[0].ApiKey.Inject[0].Format = "%s"
		require.NoError(t, ValidateArtifact(a))
		require.Empty(t, a.Warnings, "the warning must clear once header+format is set, got %v", a.Warnings)
	})

	// scheme: basic expands to Username set, Header empty (SPEC-v2 §5.4.1);
	// this shape must validate clean despite the empty header.
	t.Run("scheme_basic_post_fold_shape_is_clean", func(t *testing.T) {
		yamlBytes := []byte(`
schemaVersion: "2"
kind: mixin
name: creds-basic
permissions:
  network:
    allow:
      - github.com
credentials:
  - service: github
    apiKey:
      name: GITHUB_TOKEN
      inject:
        - domain: github.com
          scheme: basic
          username: x-access-token
`)
		art, err := LoadArtifactFromBytes(yamlBytes)
		require.NoError(t, err)
		require.NoError(t, ValidateArtifact(art))
		require.Empty(t, art.Credentials[0].ApiKey.Inject[0].Header, "scheme: basic sets no header")
		require.Equal(t, "x-access-token", art.Credentials[0].ApiKey.Inject[0].Username)
		require.Empty(t, art.Warnings)
	})

	// Regression: the v1 serviceDomains+serviceAuth fold can produce a
	// no-name, header-only apiKey that already injects; it must stay valid.
	t.Run("v1_serviceDomains_fold_without_name_stays_valid", func(t *testing.T) {
		yamlBytes := []byte(`
schemaVersion: "1"
kind: agent
name: routing-only
agent:
  image: x
network:
  allowedDomains: [api.anthropic.com]
  serviceDomains:
    api.anthropic.com: anthropic
  serviceAuth:
    anthropic:
      headerName: x-api-key
      valueFormat: "%s"
`)
		art, err := LoadArtifactFromBytes(yamlBytes)
		require.NoError(t, err)
		require.NoError(t, ValidateArtifact(art))
		require.Empty(t, art.Credentials[0].ApiKey.Name, "no credentials.sources entry means no envName")
		require.Equal(t, "x-api-key", art.Credentials[0].ApiKey.Inject[0].Header)
		require.False(t, hasWarningContaining(art.Warnings, apiKeyNameEmptyWarningPrefix),
			"the empty-name warning is v2-only, so the v1 fold must not receive it, got %v", art.Warnings)
	})

	t.Run("oauth_credential_file_structure_only_accepted", func(t *testing.T) {
		a := &Artifact{
			Manifest: Manifest{SchemaVersion: SchemaVersion, Kind: KindMixin, Name: "ok"},
			Credentials: []Credential{{
				Service: "anthropic",
				OAuth: &OAuth{
					TokenEndpoint: OAuthTokenEndpoint{Host: "h", Path: "/p"},
					Sentinels:     OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
					CredentialFile: &OAuthCredentialFile{
						Path:      "/cred",
						Structure: map[string]interface{}{"accessToken": "{{.AccessToken}}"},
					},
				},
			}},
		}
		require.NoError(t, ValidateArtifact(a))
	})
}

func TestResolvedResponseFields(t *testing.T) {
	t.Run("defaults", func(t *testing.T) {
		p := &OAuthPolicy{}
		f := p.ResolvedResponseFields()
		require.Equal(t, "access_token", f.AccessToken)
		require.Equal(t, "refresh_token", f.RefreshToken)
		require.Equal(t, "expires_in", f.ExpiresIn)
		require.Equal(t, "scope", f.Scope)
	})

	t.Run("overrides", func(t *testing.T) {
		p := &OAuthPolicy{
			ResponseFields: &OAuthResponseFields{
				AccessToken: "accessToken",
				ExpiresIn:   "expiresIn",
			},
		}
		f := p.ResolvedResponseFields()
		require.Equal(t, "accessToken", f.AccessToken)
		require.Equal(t, "refresh_token", f.RefreshToken)
		require.Equal(t, "expiresIn", f.ExpiresIn)
		require.Equal(t, "scope", f.Scope)
	})
}
