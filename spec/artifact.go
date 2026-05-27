package spec

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

// Well-known file and directory names within an artifact.
const (
	specFileName    = "spec.yaml"
	specFileNameAlt = "spec.yml"
	filesDirHome    = "files/home"
	filesDirWork    = "files/workspace"
)

// LoadFromDirectory loads a kit artifact from a local directory.
func LoadFromDirectory(dir string) (*Artifact, error) {
	info, err := os.Stat(dir)
	if err != nil {
		return nil, fmt.Errorf("artifact directory: %w", err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("artifact: %q is not a directory", dir)
	}

	readFile := func(name string) ([]byte, error) {
		return os.ReadFile(filepath.Join(dir, name))
	}

	artifact, err := parseArtifact(readFile)
	if err != nil {
		return nil, err
	}

	artifact.Files, err = collectFilesFromDir(dir)
	if err != nil {
		return nil, fmt.Errorf("artifact files: %w", err)
	}

	if err := ValidateArtifact(artifact); err != nil {
		return nil, err
	}

	return artifact, nil
}

// LoadFromFS loads a kit artifact from an fs.FS (e.g., embed.FS or os.DirFS).
func LoadFromFS(fsys fs.FS, dir string) (*Artifact, error) {
	dir = filepath.ToSlash(dir)

	readFile := func(name string) ([]byte, error) {
		return fs.ReadFile(fsys, filepath.ToSlash(filepath.Join(dir, name)))
	}

	artifact, err := parseArtifact(readFile)
	if err != nil {
		return nil, err
	}

	artifact.Files, err = collectFilesFromFS(fsys, dir)
	if err != nil {
		return nil, fmt.Errorf("artifact files: %w", err)
	}

	if err := ValidateArtifact(artifact); err != nil {
		return nil, err
	}

	return artifact, nil
}

// LoadFromBytes parses spec.yaml bytes into an Artifact, leaving Files
// unset and skipping validation. Intended for callers that obtain the
// spec.yaml separately from the file payload — e.g., the v2 OCI puller,
// which reads spec.yaml from the manifest's config blob and the files
// from a tar layer.
//
// Callers must populate Artifact.Files from their own source and then
// call ValidateArtifact to verify the result. LoadFromDirectory and
// LoadFromFS do this automatically; LoadFromBytes does not because it
// has no notion of a file source.
func LoadFromBytes(yamlBytes []byte) (*Artifact, error) {
	return parseArtifactBytes(yamlBytes)
}

// parseArtifact reads spec.yaml (or spec.yml as fallback) via readFile and
// delegates to parseArtifactBytes.
func parseArtifact(readFile func(string) ([]byte, error)) (*Artifact, error) {
	data, err := readFile(specFileName)
	if err != nil {
		data, err = readFile(specFileNameAlt)
		if err != nil {
			return nil, fmt.Errorf("artifact: %s (or %s) is required: %w", specFileName, specFileNameAlt, err)
		}
	}
	return parseArtifactBytes(data)
}

// parseArtifactBytes decodes spec.yaml bytes and applies normalization.
// It does not validate; callers that need a validated Artifact must call
// ValidateArtifact themselves (LoadFromDirectory and LoadFromFS already
// do, after populating Files).
func parseArtifactBytes(data []byte) (*Artifact, error) {
	var spec specFile
	// Strict decoding: unknown top-level (or nested) yaml keys are a hard
	// error. The schema is documented and small enough that any unrecognised
	// key is almost always a typo or a stale field the kit author hasn't
	// migrated yet. Surfacing it loudly is the whole point — yaml.Unmarshal
	// would silently drop the key and let the author think their kit was
	// being honoured.
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(&spec); err != nil {
		return nil, fmt.Errorf("artifact: invalid %s: %w", specFileName, err)
	}

	w := &warnings{}
	if err := spec.normalize(w); err != nil {
		return nil, fmt.Errorf("artifact: %w", err)
	}

	return &Artifact{
		Manifest:     spec.Manifest,
		Extends:      spec.Extends,
		Locked:       spec.Locked,
		Network:      spec.Network,
		Credentials:  spec.Credentials,
		Environment:  spec.Environment,
		Settings:     spec.Settings,
		Commands:     spec.Commands,
		OAuth:        spec.OAuth,
		AgentContext: spec.AgentContext,
		Warnings:     w.messages,
	}, nil
}

// collectFilesFromDir walks the files/ directory in a local artifact directory,
// collecting all files as ArtifactFile entries.
func collectFilesFromDir(dir string) ([]ArtifactFile, error) {
	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return nil, fmt.Errorf("resolve artifact directory: %w", err)
	}
	absDir, err := filepath.Abs(realDir)
	if err != nil {
		return nil, fmt.Errorf("resolve artifact directory: %w", err)
	}

	var files []ArtifactFile

	for _, sub := range []struct {
		dir    string
		target string
	}{
		{filepath.Join(dir, filesDirHome), TargetHome},
		{filepath.Join(dir, filesDirWork), TargetWorkspace},
	} {
		info, err := os.Stat(sub.dir)
		if err != nil || !info.IsDir() {
			continue
		}

		err = filepath.Walk(sub.dir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() {
				return nil
			}

			realPath, err := filepath.EvalSymlinks(path)
			if err != nil {
				return fmt.Errorf("resolve symlink %s: %w", path, err)
			}
			absReal, err := filepath.Abs(realPath)
			if err != nil {
				return fmt.Errorf("resolve absolute path %s: %w", realPath, err)
			}
			if absReal != absDir && !strings.HasPrefix(absReal, absDir+string(filepath.Separator)) {
				return fmt.Errorf("file %s is a symlink that escapes the artifact directory (resolves to %s)", path, absReal)
			}

			rel, err := filepath.Rel(sub.dir, path)
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)

			data, err := os.ReadFile(path)
			if err != nil {
				return fmt.Errorf("read file %s: %w", path, err)
			}

			targetInfo, err := os.Stat(realPath)
			if err != nil {
				return fmt.Errorf("stat resolved file %s: %w", realPath, err)
			}

			files = append(files, ArtifactFile{
				RelativePath: rel,
				Target:       sub.target,
				Mode:         int64(targetInfo.Mode().Perm()),
				Content:      data,
				Size:         targetInfo.Size(),
			})
			return nil
		})
		if err != nil {
			return nil, err
		}
	}

	return files, nil
}

// collectFilesFromFS walks the files/ directory within an fs.FS artifact.
func collectFilesFromFS(fsys fs.FS, dir string) ([]ArtifactFile, error) {
	var files []ArtifactFile

	for _, sub := range []struct {
		subDir string
		target string
	}{
		{filesDirHome, TargetHome},
		{filesDirWork, TargetWorkspace},
	} {
		subPath := filepath.ToSlash(filepath.Join(dir, sub.subDir))
		_, err := fs.Stat(fsys, subPath)
		if err != nil {
			continue
		}

		err = fs.WalkDir(fsys, subPath, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				return nil
			}

			rel, err := filepath.Rel(subPath, p)
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)

			data, err := fs.ReadFile(fsys, p)
			if err != nil {
				return fmt.Errorf("read file %s: %w", p, err)
			}

			info, err := d.Info()
			if err != nil {
				return fmt.Errorf("file info %s: %w", p, err)
			}

			mode := int64(info.Mode().Perm())
			if mode == 0 {
				mode = 0o644
			}

			files = append(files, ArtifactFile{
				RelativePath: rel,
				Target:       sub.target,
				Mode:         mode,
				Content:      data,
				Size:         int64(len(data)),
			})
			return nil
		})
		if err != nil {
			return nil, err
		}
	}

	return files, nil
}
