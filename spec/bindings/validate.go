package bindings

import "fmt"

// Validate checks the bindings file for structural well-formedness: every
// binding has a non-empty service name. Content-level rules (domain formats,
// requiring at least one mechanism) are intentionally deferred, matching the
// pre-existing minimal-validation philosophy.
func Validate(b *UserBindings) error {
	if b == nil {
		return nil
	}
	for service := range b.Bindings {
		if service == "" {
			return fmt.Errorf("bindings: service name cannot be empty")
		}
	}
	return nil
}
