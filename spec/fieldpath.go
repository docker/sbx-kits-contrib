package spec

import (
	"fmt"
	"reflect"
	"strings"
)

// specFileV2Type and specFileType are the reflect roots v2Field and v1Field
// descend from. Computed once at package init so a typo'd field name in a
// v1Field/v2Field call panics at program startup (and therefore in any test
// run), not silently at some later call site.
var (
	specFileV2Type = reflect.TypeOf(specFileV2{})
	specFileType   = reflect.TypeOf(SpecFile{})
)

// fieldPath walks a chain of Go struct field names starting at root and
// returns the dotted YAML path those fields decode from, read directly off
// each field's `yaml` struct tag. A field is suffixed with "[]" when its Go
// type is a slice or map AND it is not the last name in the chain — i.e. the
// chain descends into one of its elements next (matching the established
// "credentials[].apiKey.inject[].domain" style); a trailing list field (e.g.
// "setup.startup", "ports") is not decorated, since nothing indexes into it.
//
// This exists so deprecation/migration messages can reference the grammar
// itself instead of a hand-typed literal. A hand-typed path silently drifts
// when a field is renamed (this is exactly how a deprecation notice once
// told kit authors to write 'caps.network.allow', an internal field name
// that was never valid v2 YAML — the real grammar had already moved to
// 'permissions.network.allow'). fieldPath instead panics loudly the moment
// the named Go field stops existing, so a rename breaks the build/tests
// instead of quietly shipping stale guidance.
func fieldPath(root reflect.Type, names ...string) string {
	t := root
	parts := make([]string, 0, len(names))
	for i, name := range names {
		for t.Kind() == reflect.Ptr {
			t = t.Elem()
		}
		f, ok := t.FieldByName(name)
		if !ok {
			panic(fmt.Sprintf("spec: fieldPath: type %s has no field %q (chain %v)", t, name, names))
		}
		tag := strings.Split(f.Tag.Get("yaml"), ",")[0]
		if tag == "" || tag == "-" {
			panic(fmt.Sprintf("spec: fieldPath: field %q on %s has no yaml tag (chain %v)", name, t, names))
		}
		isList := f.Type.Kind() == reflect.Slice || f.Type.Kind() == reflect.Map
		if isList && i < len(names)-1 {
			tag += "[]"
		}
		parts = append(parts, tag)

		ft := f.Type
		for ft.Kind() == reflect.Ptr || ft.Kind() == reflect.Slice {
			ft = ft.Elem()
		}
		t = ft
	}
	return strings.Join(parts, ".")
}

// v2Field returns the dotted v2 grammar path for a chain of Go field names
// rooted at specFileV2 (the schemaVersion "2" decode target).
func v2Field(names ...string) string {
	return fieldPath(specFileV2Type, names...)
}

// v1Field is the v1-grammar analogue of v2Field, rooted at SpecFile (the
// schemaVersion "1" decode target — Manifest is embedded inline, so
// Manifest field names like "Kind" resolve directly against SpecFile too).
func v1Field(names ...string) string {
	return fieldPath(specFileType, names...)
}

// splitLeaf splits a dotted field path into its prefix and final segment,
// for composing "prefix.a/b"-style messages that reference two sibling
// leaf fields sharing the same parent (e.g. "credentials[].apiKey.inject[].
// header/format"). Returns ("", path) if path has no '.'.
func splitLeaf(path string) (prefix, leaf string) {
	i := strings.LastIndex(path, ".")
	if i < 0 {
		return "", path
	}
	return path[:i], path[i+1:]
}
