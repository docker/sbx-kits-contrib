package spec

import (
	"bytes"
	"fmt"
	"io"
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

// LoadFromDirectory loads a kit artifact from a local directory. All file
// content is read into memory (eager path). The returned artifact is fully
// validated.
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

	entries, err := enumerateDirFiles(dir)
	if err != nil {
		return nil, fmt.Errorf("artifact files: %w", err)
	}

	files := make([]ArtifactFile, 0, len(entries))
	for _, e := range entries {
		data, err := os.ReadFile(e.realPath)
		if err != nil {
			return nil, fmt.Errorf("artifact files: read file %s: %w", e.realPath, err)
		}
		files = append(files, ArtifactFile{
			RelativePath: e.relativePath,
			Target:       e.target,
			Mode:         e.mode,
			Content:      data,
			Size:         e.size,
		})
	}
	artifact.Files = files

	if err := ValidateArtifact(artifact); err != nil {
		return nil, err
	}

	return artifact, nil
}

// OpenFromDirectory opens a kit artifact from a local directory using the
// streaming path. Metadata is enumerated and all safety checks (symlink
// escape, path validation) are performed eagerly at load time, but file
// content is not read into memory. Each ArtifactFile.Open call opens the
// file on demand, allowing callers to process one file at a time.
//
// The returned artifact is fully validated. Streaming files have Content nil
// and ContentSource non-nil; use ArtifactFile.Open to read content, or call
// Artifact.Materialize to populate Content for all files at once.
func OpenFromDirectory(dir string) (*Artifact, error) {
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

	entries, err := enumerateDirFiles(dir)
	if err != nil {
		return nil, fmt.Errorf("artifact files: %w", err)
	}

	files := make([]ArtifactFile, 0, len(entries))
	for _, e := range entries {
		files = append(files, ArtifactFile{
			RelativePath: e.relativePath,
			Target:       e.target,
			Mode:         e.mode,
			Size:         e.size,
			ContentSource: func() (io.ReadCloser, error) {
				return os.Open(e.realPath)
			},
		})
	}
	artifact.Files = files

	if err := ValidateArtifact(artifact); err != nil {
		return nil, err
	}

	return artifact, nil
}

// LoadFromFS loads a kit artifact from an fs.FS (e.g., embed.FS or
// os.DirFS). All file content is read into memory (eager path). The
// returned artifact is fully validated.
func LoadFromFS(fsys fs.FS, dir string) (*Artifact, error) {
	dir = filepath.ToSlash(dir)

	readFile := func(name string) ([]byte, error) {
		return fs.ReadFile(fsys, filepath.ToSlash(filepath.Join(dir, name)))
	}

	artifact, err := parseArtifact(readFile)
	if err != nil {
		return nil, err
	}

	entries, err := enumerateFSFiles(fsys, dir)
	if err != nil {
		return nil, fmt.Errorf("artifact files: %w", err)
	}

	files := make([]ArtifactFile, 0, len(entries))
	for _, e := range entries {
		data, err := fs.ReadFile(fsys, e.fsPath)
		if err != nil {
			return nil, fmt.Errorf("artifact files: read file %s: %w", e.fsPath, err)
		}
		files = append(files, ArtifactFile{
			RelativePath: e.relativePath,
			Target:       e.target,
			Mode:         e.mode,
			Content:      data,
			Size:         e.size, // FileInfo.Size(), consistent with OpenFromFS
		})
	}
	artifact.Files = files

	if err := ValidateArtifact(artifact); err != nil {
		return nil, err
	}

	return artifact, nil
}

// OpenFromFS opens a kit artifact from an fs.FS (e.g., embed.FS or
// os.DirFS) using the streaming path. Metadata is enumerated eagerly but
// file content is not read into memory. Each ArtifactFile.Open call opens
// the file on demand via the FS.
//
// The returned artifact is fully validated. Streaming files have Content nil
// and ContentSource non-nil; use ArtifactFile.Open to read content, or call
// Artifact.Materialize to populate Content for all files at once.
func OpenFromFS(fsys fs.FS, dir string) (*Artifact, error) {
	dir = filepath.ToSlash(dir)

	readFile := func(name string) ([]byte, error) {
		return fs.ReadFile(fsys, filepath.ToSlash(filepath.Join(dir, name)))
	}

	artifact, err := parseArtifact(readFile)
	if err != nil {
		return nil, err
	}

	entries, err := enumerateFSFiles(fsys, dir)
	if err != nil {
		return nil, fmt.Errorf("artifact files: %w", err)
	}

	files := make([]ArtifactFile, 0, len(entries))
	for _, e := range entries {
		files = append(files, ArtifactFile{
			RelativePath: e.relativePath,
			Target:       e.target,
			Mode:         e.mode,
			Size:         e.size,
			ContentSource: func() (io.ReadCloser, error) {
				return fsys.Open(e.fsPath)
			},
		})
	}
	artifact.Files = files

	if err := ValidateArtifact(artifact); err != nil {
		return nil, err
	}

	return artifact, nil
}

// LoadArtifactFromBytes parses spec.yaml bytes into an Artifact, leaving Files
// unset and skipping validation. Intended for callers that obtain the
// spec.yaml separately from the file payload — e.g., the v2 OCI puller,
// which reads spec.yaml from the manifest's config blob and the files
// from a tar layer.
//
// Callers must populate Artifact.Files from their own source and then
// call ValidateArtifact to verify the result. LoadFromDirectory and
// LoadFromFS do this automatically; LoadArtifactFromBytes does not because it
// has no notion of a file source.
func LoadArtifactFromBytes(yamlBytes []byte) (*Artifact, error) {
	return parseArtifactBytes(yamlBytes)
}

// LoadFromBytes parses spec.yaml bytes into a normalized SpecFile.
// Normalization (v1 sugar folding, legacy field removal, and canonical
// v2 shaping for marshal) happens inside this call, mirroring LoadArtifactFromBytes.
func LoadFromBytes(yamlBytes []byte) (*SpecFile, error) {
	return parseSpecFileBytes(yamlBytes)
}

// Marshal encodes a normalized SpecFile as YAML.
func Marshal(sf *SpecFile) ([]byte, error) {
	return yaml.Marshal(sf)
}

// Materialize reads any streamed files (Content == nil, ContentSource set)
// into Content and updates Size. Files already on the eager path (Content
// non-nil) are left unchanged, making the call idempotent. ContentSource is
// cleared to nil after the content is read so the file is unambiguously on
// the eager path afterwards. Returns an error if any file has neither Content
// nor ContentSource.
//
// The operation is all-or-nothing: all content is staged in memory before any
// field on the artifact is mutated. If a read fails mid-way, the artifact is
// left entirely unchanged so callers do not observe a half-eager state.
func (a *Artifact) Materialize() error {
	// Stage phase: read all streaming files without touching a.Files.
	staged := make([][]byte, len(a.Files))
	for i := range a.Files {
		f := &a.Files[i]
		if f.Content != nil {
			continue // already eager; nothing to read
		}
		if f.ContentSource == nil {
			return fmt.Errorf("artifact: file %q has neither Content nor ContentSource", f.RelativePath)
		}
		rc, err := f.ContentSource()
		if err != nil {
			return fmt.Errorf("artifact: open %q: %w", f.RelativePath, err)
		}
		data, readErr := io.ReadAll(rc)
		if cerr := rc.Close(); readErr == nil && cerr != nil {
			return fmt.Errorf("artifact: close %q: %w", f.RelativePath, cerr)
		}
		if readErr != nil {
			return fmt.Errorf("artifact: read %q: %w", f.RelativePath, readErr)
		}
		staged[i] = data
	}
	// Commit phase: only reached when every file was read successfully.
	for i := range a.Files {
		if staged[i] == nil {
			continue // was already eager
		}
		a.Files[i].Content = staged[i]
		a.Files[i].Size = int64(len(staged[i]))
		a.Files[i].ContentSource = nil
	}
	return nil
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

// decodeSpecFile decodes spec.yaml bytes with strict field checking.
// Unknown top-level (or nested) yaml keys are a hard error. The schema
// is documented and small enough that any unrecognised key is almost
// always a typo or a stale field the kit author hasn't migrated yet.
// Surfacing it loudly is the whole point — yaml.Unmarshal would silently
// drop the key and let the author think their kit was being honoured.
func decodeSpecFile(data []byte) (SpecFile, error) {
	var spec SpecFile
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(&spec); err != nil {
		return SpecFile{}, err
	}
	return spec, nil
}

func parseSpecFileBytes(data []byte) (*SpecFile, error) {
	spec, err := decodeSpecFile(data)
	if err != nil {
		return nil, fmt.Errorf("spec: invalid %s: %w", specFileName, err)
	}
	w := &warnings{}
	if err := spec.normalize(w); err != nil {
		return nil, fmt.Errorf("spec: %w", err)
	}
	spec.compactNormalized()
	return &spec, nil
}

// parseArtifactBytes decodes spec.yaml bytes and applies normalization.
// It does not validate; callers that need a validated Artifact must call
// ValidateArtifact themselves (LoadFromDirectory and LoadFromFS already
// do, after populating Files).
func parseArtifactBytes(data []byte) (*Artifact, error) {
	spec, err := decodeSpecFile(data)
	if err != nil {
		return nil, fmt.Errorf("artifact: invalid %s: %w", specFileName, err)
	}

	w := &warnings{}
	if err := spec.normalize(w); err != nil {
		return nil, fmt.Errorf("artifact: %w", err)
	}

	// PublishedPorts is canonical at the top level in v2. normalize has
	// already promoted any v1 LegacyNetwork.PublishedPorts into
	// spec.PublishedPorts (with a deprecation warning), so this is a
	// straight copy. AllowedDomains/DeniedDomains moved to Caps.Network;
	// ServiceDomains/ServiceAuth moved to Credentials[].ApiKey.Inject.
	return &Artifact{
		Manifest:       spec.Manifest,
		Extends:        spec.Extends,
		Mixins:         spec.Mixins,
		Locked:         spec.Locked,
		Licenses:       spec.Licenses,
		PublishedPorts: spec.PublishedPorts,
		Caps:           spec.Caps,
		Credentials:    spec.Credentials.List,
		Environment:    spec.Environment,
		Commands:       spec.Commands,
		AgentContext:   spec.AgentContext,
		Warnings:       w.messages,
	}, nil
}

// dirFileEntry holds the enumerated metadata for one file in a local
// directory before the content loading strategy (eager vs streaming) is
// applied. realPath is the symlink-resolved, safety-checked absolute path.
type dirFileEntry struct {
	relativePath string
	target       string
	mode         int64
	size         int64
	realPath     string // symlink-resolved absolute path; safe to open
}

// enumerateDirFiles walks the files/ subdirectories of a local artifact
// directory, resolves symlinks, verifies no file escapes the artifact root,
// and returns per-file metadata. It does not read file content. Both the
// eager loader (LoadFromDirectory) and the streaming loader
// (OpenFromDirectory) call this function so the safety logic is never
// duplicated.
func enumerateDirFiles(dir string) ([]dirFileEntry, error) {
	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return nil, fmt.Errorf("resolve artifact directory: %w", err)
	}
	absDir, err := filepath.Abs(realDir)
	if err != nil {
		return nil, fmt.Errorf("resolve artifact directory: %w", err)
	}

	var entries []dirFileEntry

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

			targetInfo, err := os.Stat(realPath)
			if err != nil {
				return fmt.Errorf("stat resolved file %s: %w", realPath, err)
			}

			entries = append(entries, dirFileEntry{
				relativePath: rel,
				target:       sub.target,
				mode:         int64(targetInfo.Mode().Perm()),
				size:         targetInfo.Size(),
				realPath:     absReal,
			})
			return nil
		})
		if err != nil {
			return nil, err
		}
	}

	return entries, nil
}

// fsFileEntry holds the enumerated metadata for one file within an fs.FS
// before the content loading strategy (eager vs streaming) is applied.
// fsPath is the path within the FS that may be passed to fsys.Open.
type fsFileEntry struct {
	relativePath string
	target       string
	mode         int64
	size         int64
	fsPath       string // path within the FS; safe to open via fsys.Open
}

// enumerateFSFiles walks the files/ subdirectories within an fs.FS and
// returns per-file metadata. It does not read file content. Both the eager
// loader (LoadFromFS) and the streaming loader (OpenFromFS) call this
// function so the logic is never duplicated.
func enumerateFSFiles(fsys fs.FS, dir string) ([]fsFileEntry, error) {
	var entries []fsFileEntry

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

			info, err := d.Info()
			if err != nil {
				return fmt.Errorf("file info %s: %w", p, err)
			}

			mode := int64(info.Mode().Perm())
			if mode == 0 {
				mode = 0o644
			}

			entries = append(entries, fsFileEntry{
				relativePath: rel,
				target:       sub.target,
				mode:         mode,
				size:         info.Size(),
				fsPath:       p,
			})
			return nil
		})
		if err != nil {
			return nil, err
		}
	}

	return entries, nil
}
