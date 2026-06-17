package bindings

import (
	"errors"
	"testing"
)

func TestParseValue_RawAndEmpty(t *testing.T) {
	cases := []struct {
		name    string
		content string
		parser  string
		want    string
	}{
		{"empty parser is raw", "sk-ant-abc\n", "", "sk-ant-abc"},
		{"explicit raw", "sk-ant-abc\n", "raw", "sk-ant-abc"},
		{"raw preserves leading whitespace", " sk-ant-abc\n", "raw", " sk-ant-abc"},
		{"raw strips multiple trailing newlines", "tok\n\n\n", "raw", "tok"},
		{"raw strips trailing CRLF", "tok\r\n", "raw", "tok"},
		{"raw on multi-line content keeps internal newlines", "line1\nline2\n", "raw", "line1\nline2"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseValue([]byte(tc.content), tc.parser)
			if err != nil {
				t.Fatalf("ParseValue: %v", err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestParseValue_JSONPath(t *testing.T) {
	doc := []byte(`{"apiKey":"sk-top","credentials":{"token":"sk-nested","meta":{"version":"v1"}}}`)
	cases := []struct {
		name   string
		parser string
		want   string
	}{
		{"top-level key", "json:apiKey", "sk-top"},
		{"nested two-segment", "json:credentials.token", "sk-nested"},
		{"nested three-segment", "json:credentials.meta.version", "v1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseValue(doc, tc.parser)
			if err != nil {
				t.Fatalf("ParseValue(%s): %v", tc.parser, err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestParseValue_JSONPath_Misses(t *testing.T) {
	doc := []byte(`{"apiKey":"sk-top","count":42,"flag":true,"nested":{"key":"v"}}`)
	cases := []struct {
		name   string
		parser string
	}{
		{"missing top-level key", "json:missing"},
		{"missing nested key", "json:nested.missing"},
		{"walks through non-object", "json:apiKey.further"},
		{"leaf is number", "json:count"},
		{"leaf is bool", "json:flag"},
		{"leaf is object", "json:nested"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ParseValue(doc, tc.parser)
			if !errors.Is(err, ErrParserMiss) {
				t.Errorf("got err=%v, want ErrParserMiss", err)
			}
		})
	}
}

func TestParseValue_JSONPath_InvalidJSON(t *testing.T) {
	_, err := ParseValue([]byte(`{not json`), "json:foo")
	if !errors.Is(err, ErrParserMiss) {
		t.Errorf("got err=%v, want ErrParserMiss", err)
	}
}

func TestParseValue_MalformedParserSpec(t *testing.T) {
	cases := []struct {
		name   string
		parser string
	}{
		{"unknown parser", "yaml:foo"},
		{"json with empty path", "json:"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ParseValue([]byte(`{"k":"v"}`), tc.parser)
			if !errors.Is(err, ErrParserMalformed) {
				t.Errorf("got err=%v, want ErrParserMalformed", err)
			}
		})
	}
}
