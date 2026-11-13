package tck

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	tcexec "github.com/testcontainers/testcontainers-go/exec"
	"go.yaml.in/yaml/v3"
)

// dispatcherPATH is the PATH a startup command gets from the sbx startup
// dispatcher: the stock default, without anything the image's `ENV PATH` adds.
//
// `docker exec` (and so every other container assertion in this package)
// inherits the image's ENV, which is exactly what a startup command does NOT
// get. A hook that calls a binary installed under, say, ~/.opencode/bin passes
// any test run through a plain exec and then fails in a real sandbox with
// `opencode: not found`. Running startup cases under this PATH is what lets the
// TCK see that.
const dispatcherPATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

// defaultStartupStarts is how many container starts a case simulates when it
// does not say. Two is the minimum that exercises a replay: startup commands
// fire on every start, so the second run is where a hook that only works on a
// fresh container, or that keeps rewriting its own output, gets caught.
const defaultStartupStarts = 2

// startupCase is one entry of the optional `startupCommands:` list in
// <kit>/testdata/tck.yaml. It runs some of the kit's startup commands the way
// the dispatcher does and then asserts on the state they left behind.
//
// Reading a startup script cannot show that it works: the opencode OAuth import
// shipped with a jq syntax error, a binary missing from the dispatcher's PATH,
// and a loop whose first iteration ate the rest of its input, and every one of
// those failures exited 0. The only evidence is executing it and looking at
// the result, which is what a case does.
type startupCase struct {
	// Name labels the subtest.
	Name string `yaml:"name"`

	// Commands are the `description`s of the startup commands to run, in the
	// order they run on each start. Each must match exactly one command in
	// the spec. Listing more than one lets a case run a hook together with
	// the earlier hook that prepares its input, as the dispatcher would.
	Commands []string `yaml:"commands"`

	// Env is added to the dispatcher environment for every command, standing
	// in for what sandboxd injects (e.g. a GH_TOKEN sentinel).
	Env map[string]string `yaml:"env"`

	// Setup is a shell script run once, before the first start, as the
	// commands' user with the image's own environment. Use it to seed
	// fixtures the commands read.
	Setup string `yaml:"setup"`

	// Starts is how many container starts to simulate. Defaults to 2.
	Starts int `yaml:"starts"`

	// Checks run after every start, as the commands' user with the image's
	// own environment. Each must exit 0.
	Checks []startupCheck `yaml:"checks"`
}

// startupCheck is one shell assertion in a startupCase.
type startupCheck struct {
	// Name says what the check proves; it is what a failure reports.
	Name string `yaml:"name"`

	// Run is a shell script that exits 0 when the check holds.
	Run string `yaml:"run"`
}

// starts returns the number of starts to simulate, defaulted.
func (c *startupCase) starts() int {
	if c.Starts == 0 {
		return defaultStartupStarts
	}
	return c.Starts
}

// validate rejects a case that could pass without testing anything: one that
// runs no command, simulates no start, or asserts nothing.
func (c *startupCase) validate() error {
	if c.Name == "" {
		return fmt.Errorf("startupCommands: every case needs a name")
	}
	if len(c.Commands) == 0 {
		return fmt.Errorf("startupCommands %q: commands must name at least one startup command", c.Name)
	}
	if c.Starts < 0 {
		return fmt.Errorf("startupCommands %q: starts must be positive, got %d", c.Name, c.Starts)
	}
	if len(c.Checks) == 0 {
		return fmt.Errorf("startupCommands %q: at least one check is required; "+
			"a startup command that fails usually still exits 0", c.Name)
	}
	for i, check := range c.Checks {
		if check.Name == "" || strings.TrimSpace(check.Run) == "" {
			return fmt.Errorf("startupCommands %q: check %d needs both name and run", c.Name, i)
		}
	}
	return nil
}

// findStartupCommand returns the one startup command whose description is
// exactly desc. Matching on the description rather than an index keeps a case
// pointed at the same hook when commands are added or reordered, and requiring
// exactly one match keeps an ambiguous description from silently testing the
// wrong hook.
func findStartupCommand(cmds []startupCommandRef, desc string) (startupCommandRef, error) {
	var found []startupCommandRef
	for _, c := range cmds {
		if c.Description == desc {
			found = append(found, c)
		}
	}
	switch len(found) {
	case 1:
		return found[0], nil
	case 0:
		return startupCommandRef{}, fmt.Errorf("no startup command has description %q", desc)
	default:
		return startupCommandRef{}, fmt.Errorf("%d startup commands have description %q", len(found), desc)
	}
}

// startupCommandRef is the part of a spec startup command a case needs.
type startupCommandRef struct {
	Description string
	Command     []string
	User        string
}

// user returns the user the command runs as, defaulted the way the spec
// documents StartupCommand.User.
func (r startupCommandRef) user() string {
	if r.User == "" {
		return "1000"
	}
	return r.User
}

// dispatcherArgv wraps argv so it runs with only the environment the startup
// dispatcher provides plus env: `env -i` drops everything the image declares.
// Variables are sorted so the command line is the same on every run.
func dispatcherArgv(argv []string, env map[string]string) []string {
	out := []string{"env", "-i", "HOME=" + HomeDir, "PATH=" + dispatcherPATH}
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		out = append(out, k+"="+env[k])
	}
	return append(out, argv...)
}

// loadStartupCases reads the optional `startupCommands:` list from
// <Dir>/testdata/tck.yaml. Returns nil when the file or the list is absent.
func (s *Suite) loadStartupCases(t *testing.T) []startupCase {
	t.Helper()

	if s.Dir == "" {
		return nil
	}

	p := filepath.Join(s.Dir, "testdata", "tck.yaml")
	data, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		return nil
	}
	require.NoErrorf(t, err, "read %s", p)

	// Only this list is decoded; every other key belongs to another harness.
	var doc struct {
		StartupCommands []startupCase `yaml:"startupCommands"`
	}
	require.NoErrorf(t, yaml.Unmarshal(data, &doc), "parse %s", p)

	return doc.StartupCommands
}

// startupCommandRefs lists the kit's startup commands.
func (s *Suite) startupCommandRefs() []startupCommandRef {
	if s.Artifact == nil || s.Artifact.Commands == nil {
		return nil
	}
	refs := make([]startupCommandRef, 0, len(s.Artifact.Commands.Startup))
	for _, c := range s.Artifact.Commands.Startup {
		refs = append(refs, startupCommandRef{Description: c.Description, Command: c.Command, User: c.User})
	}
	return refs
}

// RunStartupCommandTests runs each case in testdata/tck.yaml's
// `startupCommands:` list: setup once, then for every simulated start, the
// named startup commands in order under the dispatcher's environment, followed
// by every check.
//
// Opt-in, because what a hook should leave behind is specific to the agent:
// the checks are the kit's own statement of that.
func (s *Suite) RunStartupCommandTests(t *testing.T, ctx context.Context, container testcontainers.Container) {
	cases := s.loadStartupCases(t)
	if len(cases) == 0 {
		return
	}

	t.Run("startup_commands", func(t *testing.T) {
		all := s.startupCommandRefs()
		for _, c := range cases {
			t.Run(c.Name, func(t *testing.T) {
				require.NoError(t, c.validate())

				cmds := make([]startupCommandRef, 0, len(c.Commands))
				for _, desc := range c.Commands {
					cmd, err := findStartupCommand(all, desc)
					require.NoError(t, err)
					cmds = append(cmds, cmd)
				}

				exec := func(user, what string, argv ...string) (int, string) {
					t.Helper()
					code, reader, err := container.Exec(ctx, argv, tcexec.WithUser(user), tcexec.Multiplexed())
					require.NoErrorf(t, err, "exec %s", what)
					return code, readOutput(t, reader)
				}

				// Setup and checks run as the first command's user. Docker does
				// not set HOME for an exec that overrides the user.
				user := cmds[0].user()
				if c.Setup != "" {
					code, out := exec(user, "setup", "env", "HOME="+HomeDir, "sh", "-c", c.Setup)
					require.Equalf(t, 0, code, "setup exited %d\n%s", code, out)
				}

				for start := 1; start <= c.starts(); start++ {
					var log strings.Builder
					for _, cmd := range cmds {
						code, out := exec(cmd.user(), cmd.Description, dispatcherArgv(cmd.Command, c.Env)...)
						fmt.Fprintf(&log, "> %s (exit %d)\n%s\n", cmd.Description, code, out)
						require.Equalf(t, 0, code, "start %d: %q exited %d\n%s", start, cmd.Description, code, log.String())
					}
					for _, check := range c.Checks {
						code, out := exec(user, check.Name, "env", "HOME="+HomeDir, "sh", "-c", check.Run)
						require.Equalf(t, 0, code, "start %d: %s\n  check exited %d: %s\n  startup output:\n%s",
							start, check.Name, code, out, log.String())
					}
				}
			})
		}
	})
}
