package bindings

import "fmt"

// Validate checks the bindings file for structural well-formedness:
// every discovery entry (when present) has exactly one of Env or File
// set, and File entries have a non-empty path. Discovery itself is
// optional — a binding with only allowedDomains is legitimate when the
// user has stored the credential in the secret store under the
// service's canonical name (the resolver consults the store before
// any user-declared discovery entries, so leaving discovery empty is
// the right way to express "trust these domains; the value lives
// where sbx secret set put it").
//
// Content-level rules (service-name pattern, allowedDomains entry
// format, env-var name patterns) are intentionally NOT enforced here
// — they belong to a future RFC, tracked alongside the Phase 3
// deferred validation rules in
// docs/specs/2026-05-29-unified-kit-spec-v2-deferred-ideas.md.
func Validate(b *UserBindings) error {
	if b == nil {
		return nil
	}
	for service, binding := range b.Bindings {
		if service == "" {
			return fmt.Errorf("bindings: service name cannot be empty")
		}
		for i, d := range binding.Discovery {
			envSet := len(d.Env) > 0
			fileSet := d.File != nil
			switch {
			case envSet && fileSet:
				return fmt.Errorf("bindings[%q].discovery[%d]: exactly one of env or file must be set, got both", service, i)
			case !envSet && !fileSet:
				return fmt.Errorf("bindings[%q].discovery[%d]: exactly one of env or file must be set, got neither", service, i)
			}
			if fileSet && d.File.Path == "" {
				return fmt.Errorf("bindings[%q].discovery[%d].file.path is required", service, i)
			}
		}
	}
	return nil
}
