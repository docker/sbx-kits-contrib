package tck

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/docker/sbx-kits-contrib/spec"
	"go.yaml.in/yaml/v3"
)

const (
	refOpen  = "${{"
	refClose = "}}"

	// refNamespace is the only `${{ … }}` namespace this package resolves.
	// Text opening any other one is left as written, bar the escape, so a kit
	// may carry `${{ github.sha }}` for something else to resolve.
	refNamespace = "kit.args."
)

// specFileNames are the accepted spellings of a kit's spec file, in the order
// the spec loader tries them.
var specFileNames = []string{"spec.yaml", "spec.yml"}

// openKitArtifact loads the kit at dir with every `${{ kit.args.<name> }}`
// reference in its spec file and under files/ replaced by its resolved value,
// bar the ones inside the spec's own args: block.
//
// Substitution runs before the spec is decoded and validated. That ordering is
// what lets an argument parameterize a field the schema type-checks or
// pattern-checks — requires.agent, a numeric resource — and not merely a
// free-form string.
//
// In the spec file the substitution is made inside the YAML scalars, not on
// the file's bytes: a value carrying a quote, a newline or its own `key:` text
// then stays the single scalar the author wrote instead of reshaping the
// document. Content under files/ is not YAML and is substituted as bytes.
func openKitArtifact(dir string) (*spec.Artifact, error) {
	// A spec file that is missing, unreadable, or not well-formed YAML fails
	// for a reason that has nothing to do with arguments, so the loader is
	// left to name it in its own terms.
	doc, specName := openSpecDocument(dir)
	if doc == nil {
		return spec.OpenFromDirectory(dir)
	}

	values, err := resolveKitArgs(dir, doc, specName)
	if err != nil {
		return nil, err
	}

	specContent, refs, err := expandSpecDocument(doc, values)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", specName, err)
	}
	if err := undeclaredError(specName, refs, values, specName); err != nil {
		return nil, err
	}

	staged, err := stageExpandedKit(dir, specName, specContent, values)
	if err != nil {
		return nil, err
	}
	if staged == "" {
		return spec.OpenFromDirectory(dir)
	}
	defer removeStaging(staged)

	artifact, err := spec.OpenFromDirectory(staged)
	if err != nil {
		return nil, err
	}
	// The staging tree is deleted when this call returns, so no file may be
	// left behind a ContentSource that would read from it later.
	if err := artifact.Materialize(); err != nil {
		return nil, err
	}
	return artifact, nil
}

// KitArgFlags renders kitName's argument values as flags for `sbx create`,
// which documents --kit-arg as a repeatable option. The kit-scoped
// <kit>.<name>=value spelling is used rather than the bare name: a create can
// carry several kits, and an unscoped value is offered to every one of them
// that happens to declare that argument name. Names are sorted so a command
// line is reproducible.
func KitArgFlags(kitName string, args map[string]string) []string {
	flags := make([]string, 0, 2*len(args))
	for _, name := range slices.Sorted(maps.Keys(args)) {
		flags = append(flags, "--kit-arg", kitName+"."+name+"="+args[name])
	}
	return flags
}

// resolveKitArgs pairs each argument the kit declares with the value the TCK
// substitutes for it: the entry under `args:` in <dir>/testdata/tck.yaml when
// there is one, otherwise the argument's declared default. A required
// argument with no value in tck.yaml is an error rather than a skip — a kit
// whose arguments cannot be resolved is a kit nothing tests.
func resolveKitArgs(dir string, doc *yaml.Node, specName string) (map[string]string, error) {
	decls, err := readArgDeclarations(doc, specName)
	if err != nil {
		return nil, err
	}
	if err := spec.ValidateArgs(decls); err != nil {
		return nil, err
	}

	tckPath := filepath.Join(dir, "testdata", "tck.yaml")
	supplied, err := readTCKArgs(tckPath)
	if err != nil {
		return nil, err
	}
	for _, name := range slices.Sorted(maps.Keys(supplied)) {
		if _, declared := decls[name]; !declared {
			return nil, fmt.Errorf("%s sets args[%q], which %s does not declare", tckPath, name, specName)
		}
	}

	values := make(map[string]string, len(decls))
	for _, name := range slices.Sorted(maps.Keys(decls)) {
		decl := decls[name]
		value, ok := supplied[name]
		if !ok {
			if decl.Default == nil {
				return nil, fmt.Errorf(
					"args[%q] is required and %s supplies no value; declare it there as `args:` with a %q entry",
					name, tckPath, name)
			}
			values[name] = *decl.Default
			continue
		}
		// ValidateArgs has already rejected a declaration whose own default
		// violates its enum or pattern, so only a tck.yaml value reaches here
		// unchecked.
		if err := decl.ValidateValue(value); err != nil {
			return nil, fmt.Errorf("%s: args[%q]: %w", tckPath, name, err)
		}
		values[name] = value
	}
	return values, nil
}

// readArgDeclarations decodes only the args: block of the parsed spec
// document. A full decode cannot run first: an unexpanded placeholder in a
// typed or pattern-checked field fails it, and these declarations are what
// tell the expansion how to replace that placeholder.
//
// A document that is not a mapping declares no arguments here; saying so is
// the loader's job, not this one's.
func readArgDeclarations(doc *yaml.Node, specName string) (map[string]spec.KitArg, error) {
	if len(doc.Content) == 0 || doc.Content[0].Kind != yaml.MappingNode {
		return nil, nil
	}
	var block struct {
		Args map[string]spec.KitArg `yaml:"args"`
	}
	if err := doc.Content[0].Decode(&block); err != nil {
		return nil, fmt.Errorf("read the args: block of %s: %w", specName, err)
	}
	return block.Args, nil
}

// readTCKArgs reads the `args:` block of a kit's testdata/tck.yaml. A missing
// file yields no values, which is the ordinary case for a kit whose arguments
// all have defaults.
func readTCKArgs(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var doc struct {
		Args map[string]string `yaml:"args"`
	}
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("parse the args: block of %s: %w", path, err)
	}
	return doc.Args, nil
}

// openSpecDocument parses the kit's spec file and returns it with the name it
// was found under, or a nil node when there is nothing readable and parseable
// to work from.
func openSpecDocument(dir string) (*yaml.Node, string) {
	for _, name := range specFileNames {
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		var doc yaml.Node
		if err := yaml.Unmarshal(data, &doc); err != nil {
			return nil, ""
		}
		return &doc, name
	}
	return nil, ""
}

// scanArgs rewrites s, replacing each `${{ kit.args.<name> }}` reference whose
// name values holds with that value, and returns every name it referenced —
// including ones values does not hold, which are left in place for the caller
// to report together.
//
// An occurrence of `${{` that opens the kit.args namespace must parse as a
// whole reference: an unclosed one, or one whose name is not a name, is an
// error rather than text that survives into an install command. A `${{` that
// opens any other namespace is copied through, and `$${{` emits a literal
// `${{` and opens nothing.
//
// A substituted value is written out as-is and never rescanned, so a value can
// carry reference-shaped text without it resolving to anything.
func scanArgs(s string, values map[string]string) (string, []string, error) {
	if !strings.Contains(s, refOpen) {
		return s, nil, nil
	}

	var b strings.Builder
	var refs []string
	for i := 0; i < len(s); {
		j := strings.Index(s[i:], refOpen)
		if j < 0 {
			b.WriteString(s[i:])
			break
		}
		j += i

		if j > i && s[j-1] == '$' {
			b.WriteString(s[i : j-1])
			b.WriteString(refOpen)
			i = j + len(refOpen)
			continue
		}

		b.WriteString(s[i:j])
		i = j + len(refOpen)

		if !opensArgNamespace(s[i:]) {
			b.WriteString(refOpen)
			continue
		}

		end := strings.Index(s[i:], refClose)
		if end < 0 {
			return "", nil, fmt.Errorf("unterminated argument reference %q: close it with %s", excerpt(s[j:]), refClose)
		}
		inner := s[i : i+end]
		// Trimmed before the prefix is cut, so nothing may sit between the
		// namespace dot and the name it selects.
		name := strings.TrimPrefix(strings.TrimSpace(inner), refNamespace)
		if !spec.ValidArgName(name) {
			return "", nil, fmt.Errorf(
				"malformed argument reference %q: an argument name starts with a letter or underscore, then letters, digits, underscores or hyphens — a dot is not part of one",
				excerpt(refOpen+inner+refClose))
		}
		i += end + len(refClose)

		refs = append(refs, name)
		if value, ok := values[name]; ok {
			b.WriteString(value)
			continue
		}
		b.WriteString(refOpen + inner + refClose)
	}
	return b.String(), refs, nil
}

// excerpt shortens text quoted back to the author so one runaway reference
// cannot print a whole file. The cut lands on a rune boundary, never inside a
// multi-byte character.
func excerpt(s string) string {
	const max = 60
	if len(s) <= max {
		return s
	}
	cut := max
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut] + "…"
}

// undeclaredError reports the references in refs that values cannot resolve.
// where names the file they were read from, which is not always the spec file
// the declaration is missing from.
func undeclaredError(where string, refs []string, values map[string]string, specName string) error {
	var missing []string
	for _, name := range refs {
		if _, ok := values[name]; !ok && !slices.Contains(missing, name) {
			missing = append(missing, name)
		}
	}
	if len(missing) == 0 {
		return nil
	}
	slices.Sort(missing)
	quoted := make([]string, len(missing))
	for i, name := range missing {
		quoted[i] = refOpen + " " + refNamespace + name + " " + refClose
	}
	return fmt.Errorf("%s references %s, which %s does not declare in its args: block",
		where, strings.Join(quoted, ", "), specName)
}

type specExpander struct {
	values  map[string]string
	refs    []string
	changed bool
}

// expandSpecDocument substitutes doc's scalars in place and re-encodes it,
// returning nil content when nothing was substituted so the caller can keep
// the author's own bytes.
func expandSpecDocument(doc *yaml.Node, values map[string]string) ([]byte, []string, error) {
	e := &specExpander{values: values}
	if err := e.walk(doc, false); err != nil {
		return nil, nil, err
	}
	if !e.changed {
		return nil, e.refs, nil
	}
	out, err := yaml.Marshal(doc)
	if err != nil {
		return nil, nil, err
	}
	return out, e.refs, nil
}

// walk substitutes n's scalars. atRoot marks the spec document's top-level
// node, the one mapping whose args key names the declaration block rather
// than ordinary content.
func (e *specExpander) walk(n *yaml.Node, atRoot bool) error {
	switch n.Kind {
	case yaml.DocumentNode:
		for _, child := range n.Content {
			if err := e.walk(child, true); err != nil {
				return err
			}
		}
	case yaml.SequenceNode:
		for _, child := range n.Content {
			if err := e.walk(child, false); err != nil {
				return err
			}
		}
	case yaml.MappingNode:
		for i := 0; i+1 < len(n.Content); i += 2 {
			key := n.Content[i]
			if err := e.checkKey(key); err != nil {
				return err
			}
			// The args block is the signed contract naming a kit's inputs, so
			// substitution must never rewrite a declaration into something its
			// author did not write — reference-shaped text in a default or a
			// description documents an input rather than using one.
			if atRoot && key.Kind == yaml.ScalarNode && key.Value == "args" {
				continue
			}
			if err := e.walk(n.Content[i+1], false); err != nil {
				return err
			}
		}
	case yaml.ScalarNode:
		return e.walkScalar(n)
	}
	return nil
}

// checkKey rejects a mapping key that names an argument. An argument
// parameterizes a value in the grammar; a key is the grammar.
//
// A key is never rewritten, so there is nothing for `$${{` to escape and the
// check does not honor it: text shaped like a reference is refused wherever it
// appears in a key. A key that is not a scalar is left alone entirely.
func (e *specExpander) checkKey(n *yaml.Node) error {
	if n.Kind != yaml.ScalarNode || !opensArgRef(n.Value) {
		return nil
	}
	return fmt.Errorf("mapping key %q references an argument, which may only stand in for a value", n.Value)
}

// opensArgNamespace reports whether s — the text just past a `${{` opener —
// names the kit-args namespace. Its notion of leading space is the same one
// that trims the name out, so no reference can read as a foreign namespace
// here and as a kit argument there.
func opensArgNamespace(s string) bool {
	return strings.HasPrefix(strings.TrimLeftFunc(s, unicode.IsSpace), refNamespace)
}

// opensArgRef reports whether s contains an opener for the kit.args namespace.
func opensArgRef(s string) bool {
	for i := 0; i < len(s); {
		j := strings.Index(s[i:], refOpen)
		if j < 0 {
			return false
		}
		i += j + len(refOpen)
		if opensArgNamespace(s[i:]) {
			return true
		}
	}
	return false
}

func (e *specExpander) walkScalar(n *yaml.Node) error {
	out, refs, err := scanArgs(n.Value, e.values)
	if err != nil {
		return err
	}
	e.refs = append(e.refs, refs...)
	if out == n.Value {
		return nil
	}
	n.Value = out
	e.changed = true
	if n.Style != yaml.SingleQuotedStyle && n.Style != yaml.DoubleQuotedStyle {
		// The scalar carries the resolver's !!str tag from before the
		// substitution. Dropping tag and style together re-infers the type
		// from the substituted text, which is the whole of the spec's quoting
		// rule: only a quoted placeholder promises a string, and every other
		// style — plain, literal, folded — asks for the ordinary inference.
		n.Tag = ""
		n.Style = 0
	}
	return nil
}

// stagedEntry is one path of a kit directory as it will be recreated in the
// staging tree. A regular file with nil content is copied from the kit
// unchanged.
type stagedEntry struct {
	rel     string
	mode    fs.FileMode
	isDir   bool
	link    string
	content []byte
}

// stageExpandedKit copies dir into a temporary tree carrying specContent as
// the spec file and every files/ reference expanded, and returns that tree's
// path. It returns "" when nothing was substituted anywhere, so a kit that
// references no argument is loaded straight from its own directory and cannot
// be perturbed by the copy.
//
// The whole directory is copied, not only the substituted files, so that a
// symlink under files/ pointing at a target elsewhere in the kit still
// resolves inside the staged root. Links are recreated as links rather than
// followed, leaving the loader something to resolve and check: a relative
// in-tree target lands inside the copy, an absolute one wherever it points.
func stageExpandedKit(dir, specName string, specContent []byte, values map[string]string) (string, error) {
	// The walk below lstats what it is given, so a kit directory that is
	// itself a symlink would yield one entry and no tree. The loader accepts
	// such a kit; resolving here keeps staging able to copy it.
	kitDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", fmt.Errorf("stage expanded kit: %w", err)
	}

	entries, expanded, err := planStaging(kitDir, specName, specContent, values)
	if err != nil || !expanded {
		return "", err
	}

	root, err := os.MkdirTemp("", "tck-kit-args-")
	if err != nil {
		return "", fmt.Errorf("stage expanded kit: %w", err)
	}
	if err := writeStaging(root, kitDir, entries); err != nil {
		removeStaging(root)
		return "", fmt.Errorf("stage expanded kit: %w", err)
	}
	return root, nil
}

// removeStaging deletes a staging tree, restoring owner write access on the
// way in: a directory staged read-only to match the kit cannot have its
// children unlinked otherwise.
func removeStaging(root string) {
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err == nil && d.IsDir() {
			_ = os.Chmod(path, 0o700)
		}
		return nil
	})
	_ = os.RemoveAll(root)
}

// planStaging walks dir, substituting the files/ content an argument reference
// may appear in and recording every other path for a verbatim copy. expanded
// reports whether anything — here or in the already-expanded spec file — was
// actually substituted.
//
// Anything that is neither a regular file, a directory nor a symlink is left
// out rather than opened: a fifo would block the walk forever, and whether
// such an entry matters to a kit is the loader's judgement to make.
func planStaging(dir, specName string, specContent []byte, values map[string]string) (entries []stagedEntry, expanded bool, err error) {
	expanded = specContent != nil

	err = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(dir, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		rel = filepath.ToSlash(rel)

		info, err := d.Info()
		if err != nil {
			return err
		}
		entry := stagedEntry{rel: rel, mode: info.Mode().Perm(), isDir: d.IsDir()}

		switch {
		case rel == specName:
			// Ahead of the symlink case: a spec file reached through a link
			// must still be staged as the substituted bytes, not as a link
			// back to text nothing has substituted.
			target, err := os.Stat(path)
			if err != nil {
				return err
			}
			entry.mode = target.Mode().Perm()
			entry.content = specContent
		case d.IsDir():
		case d.Type()&fs.ModeSymlink != 0:
			if entry.link, err = os.Readlink(path); err != nil {
				return err
			}
		case !info.Mode().IsRegular():
			return nil
		case strings.HasPrefix(rel, "files/"):
			raw, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			if !bytes.Contains(raw, []byte(refOpen)) {
				break
			}
			src := string(raw)
			out, refs, err := scanArgs(src, values)
			if err != nil {
				return fmt.Errorf("%s: %w", rel, err)
			}
			if err := undeclaredError(rel, refs, values, specName); err != nil {
				return err
			}
			if out != src {
				expanded = true
				entry.content = []byte(out)
			}
		}

		entries = append(entries, entry)
		return nil
	})
	if err != nil {
		return nil, false, fmt.Errorf("plan the expanded copy of %s: %w", dir, err)
	}
	return entries, expanded, nil
}

func writeStaging(root, kitDir string, entries []stagedEntry) error {
	for _, e := range entries {
		rel := filepath.FromSlash(e.rel)
		if err := writeStagedEntry(filepath.Join(root, rel), filepath.Join(kitDir, rel), e); err != nil {
			return err
		}
	}

	// Directories were created wide enough to write into. Narrowing them back
	// in reverse walk order narrows each one only once its own subtree is in
	// place.
	for i := len(entries) - 1; i >= 0; i-- {
		if !entries[i].isDir {
			continue
		}
		path := filepath.Join(root, filepath.FromSlash(entries[i].rel))
		if err := os.Chmod(path, entries[i].mode); err != nil {
			return err
		}
	}
	return nil
}

func writeStagedEntry(path, kitPath string, e stagedEntry) error {
	switch {
	case e.link != "":
		return os.Symlink(e.link, path)
	case e.isDir:
		return os.MkdirAll(path, e.mode|0o700)
	case e.content != nil:
		if err := os.WriteFile(path, e.content, e.mode); err != nil {
			return err
		}
	default:
		if err := copyFile(kitPath, path, e.mode); err != nil {
			return err
		}
	}
	// The umask applies to the create modes above, and a staged file's mode is
	// an assertion of the TCK's: it is what the file is created with in the
	// container.
	return os.Chmod(path, e.mode)
}

func copyFile(src, dst string, mode fs.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
