package spec

import (
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

	t.Run("unsupported_placeholder", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "/tmp/f", Content: "${HOME}/data"}},
		}
		require.ErrorContains(t, ValidateCommandsPolicy(c), "unsupported placeholder")
	})

	t.Run("supported_placeholder", func(t *testing.T) {
		c := &CommandsPolicy{
			InitFiles: []InitFile{{Path: "/tmp/f", Content: "${WORKDIR}/data"}},
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

	t.Run("credential_file_missing_template", func(t *testing.T) {
		p := &OAuthPolicy{
			Service:        "svc",
			TokenEndpoint:  OAuthTokenEndpoint{Host: "h", Path: "/p"},
			Sentinels:      OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
			CredentialFile: &OAuthCredentialFile{Path: "/cred"},
		}
		require.ErrorContains(t, ValidateOAuthPolicy(p), "credentialFile.template is required")
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
