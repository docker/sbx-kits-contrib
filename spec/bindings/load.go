package bindings

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"go.yaml.in/yaml/v3"
)

// configDirName is the per-user sbx config directory under the
// platform-conventional config root. Joined with credentialsFileName
// for the absolute path.
const (
	configDirName       = "sbx"
	credentialsFileName = "credentials.yaml"
)

// DefaultPath returns the platform-conventional path to the user
// credentials.yaml file:
//
//   - Linux/macOS: $XDG_CONFIG_HOME/sbx/credentials.yaml if XDG_CONFIG_HOME
//     is set; otherwise $HOME/.config/sbx/credentials.yaml.
//   - Windows:     %APPDATA%\sbx\credentials.yaml.
//
// Returns an empty string when none of the expected env vars / home
// directory can be resolved; callers should treat that as "no bindings
// file available" and surface an actionable error.
func DefaultPath() string {
	if runtime.GOOS == "windows" {
		if appdata := os.Getenv("APPDATA"); appdata != "" {
			return filepath.Join(appdata, configDirName, credentialsFileName)
		}
		return ""
	}
	if xdg := os.Getenv("XDG_CONFIG_HOME"); xdg != "" {
		return filepath.Join(xdg, configDirName, credentialsFileName)
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, ".config", configDirName, credentialsFileName)
}

// Load reads and parses the bindings file at path. Returns an error
// when the file is missing, malformed, or fails validation — by design,
// a missing file is NOT silently treated as "no bindings declared,"
// because that would conflate two distinct user states (haven't set up
// bindings yet vs. deliberately have no service-binding-needing kits).
// The resolver's hard-fail error message points the user at the
// expected path so first-time setup is discoverable.
func Load(path string) (*UserBindings, error) {
	if path == "" {
		return nil, fmt.Errorf("bindings: file path is empty (no XDG_CONFIG_HOME/HOME/APPDATA?)")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("bindings: read %s: %w", path, err)
	}

	var b UserBindings
	if err := yaml.Unmarshal(data, &b); err != nil {
		return nil, fmt.Errorf("bindings: parse %s: %w", path, err)
	}

	if err := Validate(&b); err != nil {
		return nil, fmt.Errorf("bindings: validate %s: %w", path, err)
	}

	return &b, nil
}
