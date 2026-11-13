package tck

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestStartupCaseValidate(t *testing.T) {
	valid := func() startupCase {
		return startupCase{
			Name:     "ok",
			Commands: []string{"hook"},
			Checks:   []startupCheck{{Name: "holds", Run: "true"}},
		}
	}

	t.Run("valid", func(t *testing.T) {
		c := valid()
		require.NoError(t, c.validate())
		require.Equal(t, defaultStartupStarts, c.starts())
	})

	t.Run("explicit_starts", func(t *testing.T) {
		c := valid()
		c.Starts = 3
		require.NoError(t, c.validate())
		require.Equal(t, 3, c.starts())
	})

	for name, tc := range map[string]struct {
		mutate func(*startupCase)
		want   string
	}{
		"missing_name":     {func(c *startupCase) { c.Name = "" }, "needs a name"},
		"no_commands":      {func(c *startupCase) { c.Commands = nil }, "at least one startup command"},
		"negative_starts":  {func(c *startupCase) { c.Starts = -1 }, "starts must be positive"},
		"no_checks":        {func(c *startupCase) { c.Checks = nil }, "at least one check"},
		"unnamed_check":    {func(c *startupCase) { c.Checks[0].Name = "" }, "needs both name and run"},
		"blank_check_body": {func(c *startupCase) { c.Checks[0].Run = "  \n" }, "needs both name and run"},
	} {
		t.Run(name, func(t *testing.T) {
			c := valid()
			tc.mutate(&c)
			require.ErrorContains(t, c.validate(), tc.want)
		})
	}
}

func TestFindStartupCommand(t *testing.T) {
	cmds := []startupCommandRef{
		{Description: "Seed", Command: []string{"sh", "-c", "seed"}, User: "agent"},
		{Description: "Import", Command: []string{"sh", "-c", "import"}},
		{Description: "Dup", Command: []string{"a"}},
		{Description: "Dup", Command: []string{"b"}},
	}

	t.Run("exact_match", func(t *testing.T) {
		got, err := findStartupCommand(cmds, "Import")
		require.NoError(t, err)
		require.Equal(t, []string{"sh", "-c", "import"}, got.Command)
		require.Equal(t, "1000", got.user(), "an unset user defaults to 1000, as the spec documents")
	})

	t.Run("declared_user", func(t *testing.T) {
		got, err := findStartupCommand(cmds, "Seed")
		require.NoError(t, err)
		require.Equal(t, "agent", got.user())
	})

	t.Run("prefix_is_not_a_match", func(t *testing.T) {
		_, err := findStartupCommand(cmds, "Imp")
		require.ErrorContains(t, err, "no startup command")
	})

	t.Run("ambiguous", func(t *testing.T) {
		_, err := findStartupCommand(cmds, "Dup")
		require.ErrorContains(t, err, "2 startup commands")
	})
}

func TestDispatcherArgv(t *testing.T) {
	got := dispatcherArgv([]string{"sh", "-c", "opencode auth export"}, map[string]string{
		"Z_LAST":   "z",
		"GH_TOKEN": "sentinel",
	})

	require.Equal(t, []string{
		"env", "-i", "HOME=" + HomeDir, "PATH=" + dispatcherPATH,
		"GH_TOKEN=sentinel", "Z_LAST=z",
		"sh", "-c", "opencode auth export",
	}, got)

	// The point of the dispatcher environment: nothing an image's ENV PATH
	// adds under the agent's home is reachable.
	require.NotContains(t, dispatcherPATH, HomeDir)
	require.False(t, strings.Contains(dispatcherPATH, "~"))
}
