package tck

import "testing"

// TestSecretServiceStored pins secretServiceStored's contract against the
// documented `sbx secret ls --service <name> --json` shapes, without
// needing a live sbx daemon. secretServiceStored itself lives in tck/e2e.go
// (package tck, not tck_test) alongside the rest of the exported e2e
// machinery, so this is a white-box test calling it directly.
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
