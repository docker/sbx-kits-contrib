// Package launch turns a kit manifest into a versioned agent launch recipe
// and renders the saved launcher that runs it inside a sandbox.
//
// The launcher is a POSIX sh script installed at LauncherPath. Clients start
// a fresh agent session by running Invocation(userArgs...) with the existing
// process APIs. The package is pure: it reads no files and runs nothing.
package launch

import (
	"errors"
	"fmt"
	"strings"

	"github.com/docker/sbx-kits-contrib/spec"
)

// Version is the recipe and launcher format version this package produces.
const Version = 1

// LauncherPath is where the saved launcher lives in the sandbox. It is on the
// captured root filesystem, outside host mounts and tmpfs, and is the same
// path older Bash launchers use.
const LauncherPath = "/usr/local/lib/sandbox/start-agent"

// Kind says what a fresh interactive session starts.
type Kind string

const (
	// KindAgent starts Binary through the saved launcher.
	KindAgent Kind = "agent"
	// KindShell starts the client's shell; the kit has no agent binary.
	KindShell Kind = "shell"
)

// Recipe is the resolved, nonsecret launch command of one sandbox.
//
// A fresh session runs Binary FixedArgs DefaultArgs "$@" when the first user
// argument is empty or starts with "-" (or there are none), and
// Binary FixedArgs "$@" otherwise.
type Recipe struct {
	Version int  `json:"version"`
	Kind    Kind `json:"kind"`
	// Binary is looked up on the sandbox's PATH unless it contains a "/".
	Binary string `json:"binary,omitempty"`
	// FixedArgs are always passed. Empty for Legacy recipes.
	FixedArgs []string `json:"fixedArgs,omitempty"`
	// DefaultArgs are dropped when the user passes a positional argument.
	DefaultArgs []string `json:"defaultArgs,omitempty"`
	// Legacy means the source only had a flat argv, so the fixed/default
	// split is unknown and all of it is in DefaultArgs, as older launchers
	// treated it.
	Legacy bool `json:"legacy,omitempty"`
}

// FromManifest resolves the recipe for a fresh interactive session of m,
// which should be the effective (inheritance-resolved) manifest.
//
// A manifest with no Binary gives a KindShell recipe. When
// m.StructuredLaunch() is set, the recipe keeps its fixed arguments and its
// interactive tail (Interactive when declared, even if empty, else Default).
// Otherwise the recipe is Legacy: DefaultArgs is InteractiveOptions, or
// RunOptions when that is empty, which is the command today's resolver runs.
func FromManifest(m *spec.Manifest) Recipe {
	if m.Binary == "" {
		return Recipe{Version: Version, Kind: KindShell}
	}
	if l := m.StructuredLaunch(); l != nil {
		return Recipe{
			Version:     Version,
			Kind:        KindAgent,
			Binary:      m.Binary,
			FixedArgs:   append([]string(nil), l.Entrypoint[1:]...),
			DefaultArgs: append([]string(nil), l.InteractiveTail()...),
		}
	}
	tail := m.InteractiveOptions
	if len(tail) == 0 {
		tail = m.RunOptions
	}
	return Recipe{
		Version:     Version,
		Kind:        KindAgent,
		Binary:      m.Binary,
		DefaultArgs: append([]string(nil), tail...),
		Legacy:      true,
	}
}

// Validate reports whether r is a recipe this package supports.
func (r Recipe) Validate() error {
	if r.Version != Version {
		return fmt.Errorf("launch recipe: unsupported version %d", r.Version)
	}
	switch r.Kind {
	case KindShell:
		if r.Binary != "" || len(r.FixedArgs) > 0 || len(r.DefaultArgs) > 0 || r.Legacy {
			return errors.New("launch recipe: a shell recipe has no binary or arguments")
		}
		return nil
	case KindAgent:
	default:
		return fmt.Errorf("launch recipe: unknown kind %q", r.Kind)
	}
	if r.Binary == "" || strings.HasPrefix(r.Binary, "-") {
		return errors.New("launch recipe: an agent recipe needs a binary that does not start with \"-\"")
	}
	if r.Legacy && len(r.FixedArgs) > 0 {
		return errors.New("launch recipe: a legacy recipe has no fixed arguments")
	}
	for _, a := range append(append([]string{r.Binary}, r.FixedArgs...), r.DefaultArgs...) {
		if strings.ContainsRune(a, 0) {
			return errors.New("launch recipe: arguments cannot contain NUL")
		}
	}
	return nil
}

// Invocation is the argv that runs the saved launcher with userArgs. Pass
// it to the process API as is; the caller does not quote anything.
func Invocation(userArgs ...string) []string {
	return append([]string{"/bin/sh", LauncherPath}, userArgs...)
}

// Render returns the launcher script for an agent recipe. Install it at
// LauncherPath, root-owned with mode 0755.
//
// The script needs only a POSIX sh. When BASH_ENV is set and bash is on
// PATH, it runs the agent through "bash -c" so that bash reads BASH_ENV (the
// sandbox's persistent environment) once before the PATH lookup, unless the
// script is already running in a bash that read it at startup, as when an
// older client runs "bash <launcher>". The agent keeps the caller's user.
//
// The header comment says the file was generated. Nothing may read it back
// to decide that a launcher is unmodified.
func Render(r Recipe) ([]byte, error) {
	if err := r.Validate(); err != nil {
		return nil, err
	}
	if r.Kind != KindAgent {
		return nil, fmt.Errorf("launch recipe: kind %q has no launcher", r.Kind)
	}
	var b strings.Builder
	fmt.Fprintf(&b, header, Version)
	if len(r.DefaultArgs) > 0 {
		fmt.Fprintf(&b, "case \"${1-}\" in\n-*|\"\") set -- %s \"$@\" ;;\nesac\n", quoteAll(r.DefaultArgs))
	}
	fmt.Fprintf(&b, "set -- %s \"$@\"\n", quoteAll(append([]string{r.Binary}, r.FixedArgs...)))
	b.WriteString(footer)
	return []byte(b.String()), nil
}

const header = `#!/bin/sh
# Generated by Docker Sandboxes (agent launcher format %d). Starts this
# sandbox's agent with the arguments given to this script.
#
# With no arguments, or when the first one is empty or starts with "-", the
# default arguments come before them. A first argument that is a
# sub-command replaces the default arguments. Fixed arguments always stay.
#
# To customize, edit as root. Edits persist across restarts and are saved in
# templates. Tools do not use this comment to tell whether you edited it.
`

// footer runs "$@". bash reads BASH_ENV when it starts non-interactively and
// not in POSIX mode, so a bash running this script already read it unless
// SHELLOPTS says posix (bash started as sh). Everywhere else, hop through
// bash -c when there is a BASH_ENV to read and a bash to read it.
const footer = `if [ -n "${BASH_ENV-}" ]; then
  case "${BASH_VERSION-}/${SHELLOPTS-}" in
  /*|*posix*)
    if command -v bash >/dev/null 2>&1; then
      exec bash -c 'exec "$@"' sbx-agent "$@"
    fi
    ;;
  esac
fi
exec "$@"
`

// quote single-quotes s for a POSIX shell. An embedded quote closes the
// string, adds an escaped quote and reopens it.
func quote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func quoteAll(args []string) string {
	q := make([]string, len(args))
	for i, a := range args {
		q[i] = quote(a)
	}
	return strings.Join(q, " ")
}
