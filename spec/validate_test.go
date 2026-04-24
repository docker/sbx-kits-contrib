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

	t.Run("invalid_persistence", func(t *testing.T) {
		m := valid
		m.Persistence = "something-else"
		require.ErrorContains(t, ValidateManifest(&m), "invalid persistence")
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
}

func TestValidateVolumes(t *testing.T) {
	t.Run("valid", func(t *testing.T) {
		require.NoError(t, ValidateVolumes(map[string]string{"/data": "size=4G"}))
	})

	t.Run("empty_path", func(t *testing.T) {
		require.ErrorContains(t, ValidateVolumes(map[string]string{"": ""}), "must not be empty")
	})

	t.Run("relative_path", func(t *testing.T) {
		require.ErrorContains(t, ValidateVolumes(map[string]string{"data": ""}), "must be an absolute path")
	})
}

func TestValidateTmpfs(t *testing.T) {
	t.Run("valid", func(t *testing.T) {
		require.NoError(t, ValidateTmpfs(map[string]string{"/tmp": "size=1G"}))
	})

	t.Run("empty_path", func(t *testing.T) {
		require.ErrorContains(t, ValidateTmpfs(map[string]string{"": ""}), "must not be empty")
	})

	t.Run("relative_path", func(t *testing.T) {
		require.ErrorContains(t, ValidateTmpfs(map[string]string{"tmp": ""}), "must be an absolute path")
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
