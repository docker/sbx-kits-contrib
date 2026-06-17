package bindings

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// ErrParserMalformed indicates the parser spec itself is invalid (unknown
// prefix, empty path after `json:`). It is distinct from a parser that runs
// successfully but finds nothing — see ErrParserMiss for that.
var ErrParserMalformed = errors.New("bindings: parser spec malformed")

// ErrParserMiss indicates the parser ran cleanly against the file content
// but the requested key was not present (or the structure didn't match).
// Resolvers treat this as "no value here" — equivalent to an unset env var
// in priority terms — rather than as a hard error.
var ErrParserMiss = errors.New("bindings: parser found no value")

// ParseValue extracts a credential value from raw file bytes according to
// the parser spec from DiscoveryFile.Parser. The supported parsers come
// directly from the RFC §Discovery Sources table:
//
//   - "" or "raw": return the file content trimmed of trailing whitespace.
//     Trailing-only trim is intentional — credentials that legitimately
//     begin with whitespace are extraordinarily rare, while files written
//     by tools like `echo "$TOKEN" > token` reliably end with a newline.
//
//   - "json:a.b.c": treat the file as JSON, walk the dotted path, and
//     return the value at the leaf as a string. Dots inside a key are not
//     escapable in this commit — the RFC leaves keys-with-dots open and a
//     follow-up can introduce a quoting form if real configs need it.
//     Non-string leaves (numbers, bools) are rejected with ErrParserMiss
//     because credentials are always strings in this codebase.
func ParseValue(content []byte, parser string) (string, error) {
	switch {
	case parser == "" || parser == "raw":
		return strings.TrimRight(string(content), " \t\r\n"), nil

	case strings.HasPrefix(parser, "json:"):
		path := strings.TrimPrefix(parser, "json:")
		if path == "" {
			return "", fmt.Errorf("%w: %q has empty json path", ErrParserMalformed, parser)
		}
		return parseJSONPath(content, path)

	default:
		return "", fmt.Errorf("%w: unknown parser %q", ErrParserMalformed, parser)
	}
}

func parseJSONPath(content []byte, path string) (string, error) {
	var root any
	if err := json.Unmarshal(content, &root); err != nil {
		return "", fmt.Errorf("%w: invalid JSON: %v", ErrParserMiss, err)
	}

	cur := root
	for _, segment := range strings.Split(path, ".") {
		m, ok := cur.(map[string]any)
		if !ok {
			return "", fmt.Errorf("%w: %q: parent of %q is not an object", ErrParserMiss, path, segment)
		}
		next, present := m[segment]
		if !present {
			return "", fmt.Errorf("%w: %q: key %q not present", ErrParserMiss, path, segment)
		}
		cur = next
	}

	s, ok := cur.(string)
	if !ok {
		return "", fmt.Errorf("%w: %q: leaf is %T, not string", ErrParserMiss, path, cur)
	}
	return s, nil
}
