package spec

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func strPtr(s string) *string { return &s }

func TestArgs_Decode(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: arg-kit
args:
  version:
    default: "latest"
    description: "Tool version to install"
    pattern: '^(latest|[0-9]+\.[0-9]+)$'
  channel:
    default: "stable"
    enum: ["stable", "beta"]
  token:
    required: true
    description: "API token"
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.NoError(t, ValidateArtifact(art))

	require.Equal(t, map[string]KitArg{
		"version": {
			Default:     strPtr("latest"),
			Description: "Tool version to install",
			Pattern:     `^(latest|[0-9]+\.[0-9]+)$`,
		},
		"channel": {
			Default: strPtr("stable"),
			Enum:    []string{"stable", "beta"},
		},
		"token": {
			Required:    true,
			Description: "API token",
		},
	}, art.Args)
}

func TestArgs_Absent_LeavesNil(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: no-args
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.Nil(t, art.Args, "absent args must leave Artifact.Args nil")
}

// A repeated argument name is caught by the YAML decoder itself, which is
// half of why args is a map rather than a list of {name: ...} entries.
func TestArgs_DuplicateName_Rejected(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: dup-args
args:
  version:
    default: "a"
  version:
    default: "b"
sandbox:
  image: my-image
`)
	_, err := LoadArtifactFromBytes(yaml)
	require.ErrorContains(t, err, `already defined`)
}

// args is v2-only: the v1 decoder is frozen, so the block is an unknown field
// there rather than a silently ignored one.
func TestArgs_InV1Spec_Rejected(t *testing.T) {
	yaml := []byte(`
schemaVersion: "1"
kind: sandbox
name: v1-args
template: my-image
args:
  version:
    default: "latest"
`)
	_, err := LoadArtifactFromBytes(yaml)
	require.ErrorContains(t, err, "args")
}

func TestValidateArgs_RequiresExactlyOneOfDefaultOrRequired(t *testing.T) {
	t.Run("both", func(t *testing.T) {
		err := ValidateArgs(map[string]KitArg{
			"version": {Default: strPtr("latest"), Required: true},
		})
		require.ErrorContains(t, err, "never required")
	})

	t.Run("neither", func(t *testing.T) {
		err := ValidateArgs(map[string]KitArg{
			"version": {Description: "no default, not required"},
		})
		require.ErrorContains(t, err, "must declare either a default or required: true")
	})
}

// An empty default is a real default: the argument is optional and expands to
// nothing, which is distinct from having declared no default at all.
func TestValidateArgs_EmptyStringDefaultIsADefault(t *testing.T) {
	require.NoError(t, ValidateArgs(map[string]KitArg{
		"extra_flags": {Default: strPtr("")},
	}))
}

func TestValidateArgs_EnumAndPatternMutuallyExclusive(t *testing.T) {
	err := ValidateArgs(map[string]KitArg{
		"channel": {Default: strPtr("stable"), Enum: []string{"stable"}, Pattern: "^s.*$"},
	})
	require.ErrorContains(t, err, "redundant")
}

func TestValidateArgs_InvalidName(t *testing.T) {
	err := ValidateArgs(map[string]KitArg{
		"kit.args.version": {Required: true},
	})
	require.ErrorContains(t, err, "not a valid argument name")
}

func TestValidateArgs_InvalidPattern(t *testing.T) {
	err := ValidateArgs(map[string]KitArg{
		"version": {Required: true, Pattern: "([0-9]+"},
	})
	require.ErrorContains(t, err, "not a valid regexp")
}

func TestValidateArgs_DuplicateEnumMember(t *testing.T) {
	err := ValidateArgs(map[string]KitArg{
		"channel": {Default: strPtr("stable"), Enum: []string{"stable", "beta", "stable"}},
	})
	require.ErrorContains(t, err, "duplicated")
}

func TestValidateArgs_DefaultMustSatisfyItsOwnConstraint(t *testing.T) {
	t.Run("enum", func(t *testing.T) {
		err := ValidateArgs(map[string]KitArg{
			"channel": {Default: strPtr("nightly"), Enum: []string{"stable", "beta"}},
		})
		require.ErrorContains(t, err, `args["channel"].default`)
		require.ErrorContains(t, err, `is not one of "stable", "beta"`)
	})

	t.Run("pattern", func(t *testing.T) {
		err := ValidateArgs(map[string]KitArg{
			"version": {Default: strPtr("v1"), Pattern: `^[0-9]+$`},
		})
		require.ErrorContains(t, err, `args["version"].default`)
		require.ErrorContains(t, err, "does not match pattern")
	})
}

func TestValidateArgs_ReportsTheSameArgumentEveryTime(t *testing.T) {
	args := map[string]KitArg{
		"aaa": {Required: true, Pattern: "([0-9]+"},
		"zzz": {Required: true, Pattern: "([0-9]+"},
	}
	for range 10 {
		require.ErrorContains(t, ValidateArgs(args), `args["aaa"]`)
	}
}

func TestKitArgValidateValue_PatternMatchesWholeValue(t *testing.T) {
	digits := KitArg{Required: true, Pattern: `[0-9]+`}

	require.NoError(t, digits.ValidateValue("123"))
	require.ErrorContains(t, digits.ValidateValue("v123"), "does not match pattern")
	require.ErrorContains(t, digits.ValidateValue("123v"), "does not match pattern")

	// Anchoring is applied by the engine rather than by measuring the first
	// match, so an alternation still gets to try its longer branch.
	alt := KitArg{Required: true, Pattern: `a|ab`}
	require.NoError(t, alt.ValidateValue("ab"))
}

func TestKitArgValidateValue_Enum(t *testing.T) {
	channel := KitArg{Required: true, Enum: []string{"stable", "beta"}}

	require.NoError(t, channel.ValidateValue("beta"))
	require.ErrorContains(t, channel.ValidateValue("nightly"), `is not one of "stable", "beta"`)
}

func TestKitArgValidateValue_Unconstrained(t *testing.T) {
	require.NoError(t, KitArg{Required: true}.ValidateValue("anything at all"))
}

func TestValidateArtifact_RejectsBadArgs(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: bad-args
args:
  version:
    default: "latest"
    required: true
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.ErrorContains(t, ValidateArtifact(art), `args["version"]`)
}
