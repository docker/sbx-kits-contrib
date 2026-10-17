package tck

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/stretchr/testify/require"
	"go.yaml.in/yaml/v3"
)

func TestScanArgs(t *testing.T) {
	values := map[string]string{"version": "1.20", "api-token": "shhh"}

	t.Run("replaces_declared_reference", func(t *testing.T) {
		out, refs, err := scanArgs(`VERSION: "${{ kit.args.version }}"`, values)
		require.NoError(t, err)
		require.Equal(t, []string{"version"}, refs)
		require.Equal(t, `VERSION: "1.20"`, out)
	})

	t.Run("tolerates_whitespace_and_hyphenated_names", func(t *testing.T) {
		out, _, err := scanArgs("${{kit.args.api-token}} ${{   kit.args.version   }}", values)
		require.NoError(t, err)
		require.Equal(t, "shhh 1.20", out)
	})

	t.Run("leaves_other_namespaces_alone", func(t *testing.T) {
		src := "${WORKDIR} ${{ github.sha }} $HOME ${{ kit.other.version }} ${{ matrix.kit }}"
		out, refs, err := scanArgs(src, values)
		require.NoError(t, err)
		require.Empty(t, refs)
		require.Equal(t, src, out)
	})

	t.Run("doubled_dollar_escapes_the_opener", func(t *testing.T) {
		out, refs, err := scanArgs("literal $${{ kit.args.version }} and real ${{ kit.args.version }}", values)
		require.NoError(t, err)
		require.Equal(t, []string{"version"}, refs, "the escaped occurrence is not a reference")
		require.Equal(t, "literal ${{ kit.args.version }} and real 1.20", out)
	})

	t.Run("escape_consumes_exactly_one_dollar", func(t *testing.T) {
		out, refs, err := scanArgs("$$${{ kit.args.version }}", values)
		require.NoError(t, err)
		require.Empty(t, refs)
		require.Equal(t, "$${{ kit.args.version }}", out)
	})

	t.Run("unicode_space_opens_a_reference", func(t *testing.T) {
		out, refs, err := scanArgs("${{\u00a0kit.args.version\u00a0}}", values)
		require.NoError(t, err)
		require.Equal(t, []string{"version"}, refs,
			"a non-breaking space is space to both halves of the scan")
		require.Equal(t, "1.20", out)
	})

	t.Run("space_after_the_namespace_dot_is_malformed", func(t *testing.T) {
		_, _, err := scanArgs("${{ kit.args. version }}", values)
		require.ErrorContains(t, err, `malformed argument reference "${{ kit.args. version }}"`)
	})

	t.Run("dotted_name_is_malformed", func(t *testing.T) {
		_, _, err := scanArgs("${{ kit.args.foo.bar }}", values)
		require.ErrorContains(t, err, `malformed argument reference "${{ kit.args.foo.bar }}"`)
		require.ErrorContains(t, err, "a dot is not part of one")
	})

	t.Run("unterminated_reference_is_an_error", func(t *testing.T) {
		_, _, err := scanArgs("install --version ${{ kit.args.version", values)
		require.ErrorContains(t, err, `unterminated argument reference "${{ kit.args.version"`)
		require.ErrorContains(t, err, "close it with }}")
	})

	t.Run("reports_every_referenced_name", func(t *testing.T) {
		_, refs, err := scanArgs("${{ kit.args.zeta }} ${{ kit.args.alpha }} ${{ kit.args.zeta }}", nil)
		require.NoError(t, err)
		require.Equal(t, []string{"zeta", "alpha", "zeta"}, refs)
	})

	t.Run("undeclared_reference_is_left_in_place", func(t *testing.T) {
		out, refs, err := scanArgs("${{ kit.args.nope }}", values)
		require.NoError(t, err)
		require.Equal(t, []string{"nope"}, refs)
		require.Equal(t, "${{ kit.args.nope }}", out)
	})

	t.Run("a_substituted_value_is_not_rescanned", func(t *testing.T) {
		out, refs, err := scanArgs("${{ kit.args.version }}", map[string]string{
			"version":   "${{ kit.args.api-token }}",
			"api-token": "shhh",
		})
		require.NoError(t, err)
		require.Equal(t, []string{"version"}, refs)
		require.Equal(t, "${{ kit.args.api-token }}", out)
	})
}

func TestExpandSpecDocument(t *testing.T) {
	expand := func(t *testing.T, src string, values map[string]string) ([]byte, error) {
		t.Helper()
		var doc yaml.Node
		require.NoError(t, yaml.Unmarshal([]byte(src), &doc))
		out, _, err := expandSpecDocument(&doc, values)
		return out, err
	}

	t.Run("value_reshaping_the_document_stays_one_scalar", func(t *testing.T) {
		hostile := "he said \"hi\"\nname: not-a-key\n- not an item"
		out, err := expand(t, "description: \"${{ kit.args.text }}\"\nname: real\n",
			map[string]string{"text": hostile})
		require.NoError(t, err)

		var got struct {
			Description string `yaml:"description"`
			Name        string `yaml:"name"`
		}
		require.NoError(t, yaml.Unmarshal(out, &got))
		require.Equal(t, hostile, got.Description)
		require.Equal(t, "real", got.Name, "the substituted value did not introduce a key")
	})

	t.Run("unquoted_placeholder_re_infers_its_type", func(t *testing.T) {
		out, err := expand(t, "cpu: ${{ kit.args.cpu }}\n", map[string]string{"cpu": "1.20"})
		require.NoError(t, err)

		var got struct {
			CPU float64 `yaml:"cpu"`
		}
		require.NoError(t, yaml.Unmarshal(out, &got))
		require.InDelta(t, 1.20, got.CPU, 0)
	})

	t.Run("block_scalars_re_infer_their_type_too", func(t *testing.T) {
		for _, style := range []string{">-", "|-"} {
			out, err := expand(t, "cpu: "+style+"\n  ${{ kit.args.cpu }}\n", map[string]string{"cpu": "1.20"})
			require.NoErrorf(t, err, "style %s", style)

			var got struct {
				CPU float64 `yaml:"cpu"`
			}
			require.NoErrorf(t, yaml.Unmarshal(out, &got), "style %s decodes: %s", style, out)
			require.InDeltaf(t, 1.20, got.CPU, 0, "style %s", style)
		}
	})

	t.Run("quoted_placeholder_stays_a_string", func(t *testing.T) {
		for _, quote := range []string{`"`, "'"} {
			out, err := expand(t, "cpu: "+quote+"${{ kit.args.cpu }}"+quote+"\n", map[string]string{"cpu": "1.20"})
			require.NoErrorf(t, err, "quote %s", quote)

			var got struct {
				CPU any `yaml:"cpu"`
			}
			require.NoErrorf(t, yaml.Unmarshal(out, &got), "quote %s", quote)
			require.Equalf(t, "1.20", got.CPU, "a quoted placeholder stays a string under %s", quote)
		}
	})

	t.Run("reference_in_a_mapping_key_is_an_error", func(t *testing.T) {
		_, err := expand(t, "environment:\n  ${{ kit.args.name }}: value\n", map[string]string{"name": "K"})
		require.ErrorContains(t, err,
			`mapping key "${{ kit.args.name }}" references an argument, which may only stand in for a value`)
	})

	t.Run("escaping_does_not_excuse_a_kit_args_key", func(t *testing.T) {
		_, err := expand(t, "environment:\n  \"$${{ kit.args.name }}\": value\n", map[string]string{"name": "K"})
		require.ErrorContains(t, err, `mapping key "$${{ kit.args.name }}" references an argument`)
	})

	t.Run("unicode_space_does_not_disguise_a_key", func(t *testing.T) {
		_, err := expand(t, "environment:\n  \"${{\u00a0kit.args.name }}\": value\n", map[string]string{"name": "K"})
		require.ErrorContains(t, err, "references an argument")
	})

	t.Run("foreign_namespace_key_passes_through", func(t *testing.T) {
		var doc yaml.Node
		require.NoError(t, yaml.Unmarshal([]byte(
			"environment:\n  \"$${{ github.sha }}\": \"${{ kit.args.v }}\"\n"), &doc))
		_, _, err := expandSpecDocument(&doc, map[string]string{"v": "X"})
		require.NoError(t, err)

		env := doc.Content[0].Content[1]
		require.Equal(t, "$${{ github.sha }}", env.Content[0].Value, "keys are never rewritten")
		require.Equal(t, "X", env.Content[1].Value)
	})

	t.Run("complex_key_contents_are_left_alone", func(t *testing.T) {
		var doc yaml.Node
		require.NoError(t, yaml.Unmarshal([]byte(
			"? [a, \"${{ kit.args.v }}\"]\n: keyed\nname: \"${{ kit.args.v }}\"\n"), &doc))
		_, _, err := expandSpecDocument(&doc, map[string]string{"v": "X"})
		require.NoError(t, err)

		root := doc.Content[0]
		require.Equal(t, yaml.SequenceNode, root.Content[0].Kind)
		require.Equal(t, "${{ kit.args.v }}", root.Content[0].Content[1].Value)
		require.Equal(t, "X", root.Content[3].Value, "an ordinary value alongside it is still substituted")
	})

	t.Run("the_args_block_is_never_substituted", func(t *testing.T) {
		var doc yaml.Node
		require.NoError(t, yaml.Unmarshal([]byte(
			"args:\n  literal:\n    default: \"${{ kit.args.other }}\"\n"+
				"    description: \"see ${{ kit.args.nosuch }}\"\nname: \"${{ kit.args.other }}\"\n"), &doc))
		_, refs, err := expandSpecDocument(&doc, map[string]string{"other": "X", "literal": "Y"})
		require.NoError(t, err)
		require.Equal(t, []string{"other"}, refs, "references inside args: are not collected")

		block := doc.Content[0].Content[1]
		require.Equal(t, "${{ kit.args.other }}", block.Content[1].Content[1].Value)
		require.Equal(t, "see ${{ kit.args.nosuch }}", block.Content[1].Content[3].Value)
		require.Equal(t, "X", doc.Content[0].Content[3].Value)
	})

	t.Run("a_nested_args_key_is_ordinary_content", func(t *testing.T) {
		var doc yaml.Node
		require.NoError(t, yaml.Unmarshal([]byte(
			"args:\n  v:\n    default: \"1.2.3\"\n"+
				"sandbox:\n  build:\n    args:\n      VERSION: \"${{ kit.args.v }}\"\n"), &doc))
		_, refs, err := expandSpecDocument(&doc, map[string]string{"v": "1.2.3"})
		require.NoError(t, err)
		require.Equal(t, []string{"v"}, refs)

		// sandbox.build.args carries Docker build arguments, which the spec is
		// explicit are not the kit's own args block.
		build := doc.Content[0].Content[3].Content[1]
		require.Equal(t, "1.2.3", build.Content[1].Content[1].Value)
	})

	t.Run("no_reference_leaves_the_authors_bytes", func(t *testing.T) {
		out, err := expand(t, "name: plain\n", map[string]string{"v": "x"})
		require.NoError(t, err)
		require.Nil(t, out)
	})
}

func TestExcerptCutsOnARuneBoundary(t *testing.T) {
	s := strings.Repeat("a", 59) + "é" + strings.Repeat("b", 20)
	got := excerpt(s)

	require.True(t, utf8.ValidString(got), "excerpt must not split a multi-byte character")
	require.Equal(t, strings.Repeat("a", 59)+"…", got)
}

func TestKitArgFlags(t *testing.T) {
	require.Equal(t,
		[]string{
			"--kit-arg", "my-kit.alpha=1", "--kit-arg", "my-kit.beta=2",
			"--kit-arg", "my-kit.gamma=3", "--kit-arg", "my-kit.token=dummy-for-ci",
		},
		KitArgFlags("my-kit", map[string]string{
			"token": "dummy-for-ci", "gamma": "3", "alpha": "1", "beta": "2",
		}),
		"values are scoped to the kit and ordered by name")
	require.Empty(t, KitArgFlags("my-kit", nil))
}

func TestResolveKitArgs(t *testing.T) {
	resolve := func(t *testing.T, dir string) (map[string]string, error) {
		t.Helper()
		doc, name := openSpecDocument(dir)
		require.NotNil(t, doc, "fixture %s has no parseable spec file", dir)
		return resolveKitArgs(dir, doc, name)
	}

	t.Run("tck_yaml_value_beats_the_default", func(t *testing.T) {
		values, err := resolve(t, "testdata/args-install")
		require.NoError(t, err)
		require.Equal(t, "supplied by tck.yaml", values["greeting"])
		require.Equal(t, "1.20", values["version"], "an argument tck.yaml omits falls back to its default")
		require.Equal(t, "dummy-for-ci", values["token"])
	})

	t.Run("required_without_a_value_fails", func(t *testing.T) {
		_, err := resolve(t, "testdata/args-required-missing")
		require.ErrorContains(t, err, `args["token"] is required`)
		require.ErrorContains(t, err,
			filepath.Join("testdata", "args-required-missing", "testdata", "tck.yaml")+" supplies no value")
		require.ErrorContains(t, err, `declare it there as `+"`args:`"+` with a "token" entry`)
	})

	t.Run("value_violating_its_enum_fails", func(t *testing.T) {
		_, err := resolve(t, "testdata/args-bad-value")
		require.ErrorContains(t, err, filepath.Join("testdata", "args-bad-value", "testdata", "tck.yaml"))
		require.ErrorContains(t, err, `args["channel"]: "beta" is not one of "stable", "nightly"`)
	})

	t.Run("undeclared_tck_yaml_value_fails", func(t *testing.T) {
		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(
			"schemaVersion: \"2\"\nkind: mixin\nname: stray\n"), 0o644))
		require.NoError(t, os.Mkdir(filepath.Join(dir, "testdata"), 0o755))
		require.NoError(t, os.WriteFile(filepath.Join(dir, "testdata", "tck.yaml"), []byte(
			"args:\n  nobody: \"x\"\n"), 0o644))

		_, err := resolve(t, dir)
		require.ErrorContains(t, err, `sets args["nobody"], which spec.yaml does not declare`)
	})
}

func TestNewSuiteFromDirSubstitutesArgs(t *testing.T) {
	t.Run("pattern_checked_field", func(t *testing.T) {
		suite, err := NewSuiteFromDir("testdata/args-requires-agent")
		require.NoError(t, err)
		require.Equal(t, "codex", suite.Artifact.Requires.Agent)
		require.Equal(t, wellKnownTemplates["codex"], suite.Image,
			"image resolution reads the substituted affinity")
	})

	t.Run("quoted_reference_stays_a_string", func(t *testing.T) {
		suite, err := NewSuiteFromDir("testdata/args-install")
		require.NoError(t, err)
		require.Equal(t, "1.20", suite.Artifact.Environment.Variables["ARGS_FIXTURE_VERSION"])
		require.Equal(t, "dummy-for-ci", suite.Artifact.Environment.Variables["ARGS_FIXTURE_TOKEN"])
	})

	t.Run("files_payload", func(t *testing.T) {
		suite, err := NewSuiteFromDir("testdata/args-install")
		require.NoError(t, err)
		require.Len(t, suite.Artifact.Files, 1)

		rc, err := suite.Artifact.Files[0].Open()
		require.NoError(t, err)
		defer rc.Close()
		content, err := io.ReadAll(rc)
		require.NoError(t, err)
		require.Equal(t, "version=1.20\nliteral=${{ kit.args.version }}\n", string(content),
			"files/ content is substituted, and $${{ emits a literal opener")
	})

	t.Run("undeclared_reference", func(t *testing.T) {
		_, err := NewSuiteFromDir("testdata/args-undeclared")
		require.ErrorContains(t, err,
			"spec.yaml references ${{ kit.args.token }}, which spec.yaml does not declare in its args: block")
	})

	t.Run("malformed_reference_under_files", func(t *testing.T) {
		dir := writeKit(t, map[string]string{
			"spec.yaml":         "schemaVersion: \"2\"\nkind: mixin\nname: bad-ref\nargs:\n  v:\n    default: \"1\"\n",
			"files/home/run.sh": "echo ${{ kit.args.v.patch }}\n",
		})

		_, err := NewSuiteFromDir(dir)
		require.ErrorContains(t, err, "files/home/run.sh: malformed argument reference")
	})

	t.Run("declarations_reach_the_artifact_untouched", func(t *testing.T) {
		suite, err := NewSuiteFromDir("testdata/args-block-literal")
		require.NoError(t, err)

		literal := suite.Artifact.Args["literal"]
		require.Equal(t, "${{ kit.args.other }}", *literal.Default)
		require.Equal(t, "prose naming ${{ kit.args.nosuch }}, which no declaration answers for",
			literal.Description, "an undeclared name in prose is prose, not a reference")
		require.Equal(t, "${{ kit.args.other }}",
			suite.Artifact.Environment.Variables["ARGS_FIXTURE_LITERAL"],
			"the declared default ships as the value it is, unrescanned")
	})

	t.Run("value_that_would_reshape_the_spec_survives_whole", func(t *testing.T) {
		hostile := "he said \"hi\"\nKEEP: hijacked"
		tckYAML, err := yaml.Marshal(map[string]any{"args": map[string]string{"note": hostile}})
		require.NoError(t, err)

		dir := writeKit(t, map[string]string{
			"spec.yaml": "schemaVersion: \"2\"\nkind: mixin\nname: hostile-value\n" +
				"args:\n  note:\n    required: true\n" +
				"environment:\n  variables:\n    NOTE: \"${{ kit.args.note }}\"\n    KEEP: \"sentinel\"\n",
			"testdata/tck.yaml": string(tckYAML),
		})

		suite, err := NewSuiteFromDir(dir)
		require.NoError(t, err)
		require.Equal(t, hostile, suite.Artifact.Environment.Variables["NOTE"])
		require.Equal(t, "sentinel", suite.Artifact.Environment.Variables["KEEP"],
			"the substituted value must not introduce a key of its own")
	})
}

func TestNewSuiteFromDirWithoutArgsIsUntouched(t *testing.T) {
	suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
	require.NoError(t, err)
	require.Len(t, suite.Artifact.Files, 1)

	// Content nil with a live ContentSource is the streaming path: a kit that
	// references no argument is loaded from its own directory, never from a
	// staged copy that would have been materialized eagerly.
	f := suite.Artifact.Files[0]
	require.Nil(t, f.Content)
	require.NotNil(t, f.ContentSource)

	onDisk, err := os.ReadFile(filepath.Join(
		"..", "spec", "testdata", "sample-mixin", "files", "home", filepath.FromSlash(f.RelativePath)))
	require.NoError(t, err)
	rc, err := f.Open()
	require.NoError(t, err)
	defer rc.Close()
	streamed, err := io.ReadAll(rc)
	require.NoError(t, err)
	require.Equal(t, onDisk, streamed)
}

func TestNewSuiteFromDirBrokenYAMLIsNotAnArgsError(t *testing.T) {
	dir := writeKit(t, map[string]string{
		"spec.yaml": "schemaVersion: \"2\"\nkind: mixin\n  name: bad-indent\n",
	})

	_, err := NewSuiteFromDir(dir)
	require.Error(t, err)
	require.NotContains(t, err.Error(), "args",
		"a YAML syntax error belongs to the loader, not to argument resolution")
	require.ErrorContains(t, err, "mapping values are not allowed in this context")
}

// TestSuiteArgsInstallExecution runs the fixture through the same path a real
// kit takes, so the install commands reach `sh -c` with their arguments
// already substituted — an unexpanded `${{ … }}` is a shell bad substitution
// and exits non-zero.
func TestSuiteArgsInstallExecution(t *testing.T) {
	suite, err := NewSuiteFromDir("testdata/args-install")
	require.NoError(t, err)
	suite.RunAll(t)
}

// writeKit writes a throwaway kit directory from kit-relative slash paths.
func writeKit(t *testing.T, files map[string]string) string {
	t.Helper()

	dir := t.TempDir()
	for rel, content := range files {
		path := filepath.Join(dir, filepath.FromSlash(rel))
		require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
		require.NoError(t, os.WriteFile(path, []byte(content), 0o644))
	}
	return dir
}
