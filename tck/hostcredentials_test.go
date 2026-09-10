package tck_test

import (
	"encoding/json"
	"fmt"
	"testing"
)

// secretServiceStored reports whether the JSON emitted by
// `sbx secret ls --service <name> --json` declares at least one stored
// secret for that service. The `secrets` key must be present in the decoded
// document — its absence is treated as an unrecognized payload shape, not as
// zero entries — while a present-but-empty array means the service has
// nothing stored. Unknown keys besides `secrets` are tolerated.
func secretServiceStored(raw []byte) (bool, error) {
	var doc struct {
		Secrets *[]json.RawMessage `json:"secrets"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return false, err
	}
	if doc.Secrets == nil {
		return false, fmt.Errorf(`missing "secrets" key in: %s`, raw)
	}
	return len(*doc.Secrets) > 0, nil
}

// TestSecretServiceStored pins secretServiceStored's contract against the
// documented `sbx secret ls --service <name> --json` shapes, without
// needing a live sbx daemon.
func TestSecretServiceStored(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		want    bool
		wantErr bool
	}{
		{name: "zero entries", raw: `{"secrets": []}`, want: false},
		{name: "one entry", raw: `{"secrets": [{"name": "bedrock"}]}`, want: true},
		{name: "malformed json", raw: `not json`, wantErr: true},
		{name: "missing secrets key", raw: `{}`, wantErr: true},
		{name: "different document shape", raw: `{"other": []}`, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := secretServiceStored([]byte(tt.raw))
			if tt.wantErr {
				if err == nil {
					t.Fatalf("secretServiceStored(%q): got nil error, want non-nil", tt.raw)
				}
				return
			}
			if err != nil {
				t.Fatalf("secretServiceStored(%q): got error %v, want nil", tt.raw, err)
			}
			if got != tt.want {
				t.Fatalf("secretServiceStored(%q) = %v, want %v", tt.raw, got, tt.want)
			}
		})
	}
}
