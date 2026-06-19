package spec

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"testing"
	"testing/fstest"

	"github.com/stretchr/testify/require"
)

// minimalMixinYAML is reusable spec.yaml content for tests that need a valid
// kit without caring about network / credentials / commands specifics.
const minimalMixinYAML = `schemaVersion: "1"
kind: mixin
name: stream-test
displayName: Stream Test
description: "streaming path unit test fixture"
`

// TestArtifactFile_Open covers the Open() precedence rules.
func TestArtifactFile_Open(t *testing.T) {
	t.Run("content_only", func(t *testing.T) {
		f := &ArtifactFile{
			RelativePath: "test.txt",
			Target:       TargetHome,
			Content:      []byte("hello"),
		}
		rc, err := f.Open()
		require.NoError(t, err)
		got, err := io.ReadAll(rc)
		require.NoError(t, err)
		require.NoError(t, rc.Close(), "Close must be safe after full read")
		require.Equal(t, []byte("hello"), got)
	})

	t.Run("content_source_only", func(t *testing.T) {
		want := []byte("streamed bytes")
		f := &ArtifactFile{
			RelativePath: "test.txt",
			Target:       TargetHome,
			ContentSource: func() (io.ReadCloser, error) {
				return io.NopCloser(bytes.NewReader(want)), nil
			},
		}
		rc, err := f.Open()
		require.NoError(t, err)
		got, err := io.ReadAll(rc)
		require.NoError(t, err)
		_ = rc.Close()
		require.Equal(t, want, got)
	})

	t.Run("neither_returns_error", func(t *testing.T) {
		f := &ArtifactFile{RelativePath: "test.txt", Target: TargetHome}
		_, err := f.Open()
		require.Error(t, err, "Open with neither Content nor ContentSource must error")
	})

	t.Run("both_set_prefers_content", func(t *testing.T) {
		sourceCalled := false
		f := &ArtifactFile{
			RelativePath: "test.txt",
			Target:       TargetHome,
			Content:      []byte("from content"),
			ContentSource: func() (io.ReadCloser, error) {
				sourceCalled = true
				return io.NopCloser(bytes.NewReader([]byte("from source"))), nil
			},
		}
		rc, err := f.Open()
		require.NoError(t, err)
		got, err := io.ReadAll(rc)
		_ = rc.Close()
		require.NoError(t, err)
		require.Equal(t, []byte("from content"), got, "Content must be preferred over ContentSource")
		require.False(t, sourceCalled, "ContentSource must not be called when Content is non-nil")
	})
}

// TestOpenFromDirectory_MetadataParity asserts that OpenFromDirectory and
// LoadFromDirectory produce identical metadata for every file, that the
// streaming artifact has Content==nil and ContentSource!=nil, and that
// reading each file via Open() yields the same bytes as the eager Content.
func TestOpenFromDirectory_MetadataParity(t *testing.T) {
	for _, dir := range []string{
		"testdata/sample-mixin",
		"testdata/sample-agent",
		"testdata/sample-agent-v2",
	} {
		dir := dir
		t.Run(dir, func(t *testing.T) {
			eager, err := LoadFromDirectory(dir)
			require.NoError(t, err)

			streaming, err := OpenFromDirectory(dir)
			require.NoError(t, err)

			require.Equal(t, eager.Manifest.Name, streaming.Manifest.Name)
			require.Len(t, streaming.Files, len(eager.Files),
				"streaming and eager must have the same number of files")

			// Index eager files for lookup
			eagerMap := make(map[string]ArtifactFile, len(eager.Files))
			for _, f := range eager.Files {
				eagerMap[f.Target+"/"+f.RelativePath] = f
			}

			for i := range streaming.Files {
				sf := &streaming.Files[i]
				key := sf.Target + "/" + sf.RelativePath
				ef, ok := eagerMap[key]
				require.True(t, ok, "streaming file %q not found in eager result", key)

				// Metadata must match
				require.Equal(t, ef.RelativePath, sf.RelativePath, "RelativePath mismatch for %s", key)
				require.Equal(t, ef.Target, sf.Target, "Target mismatch for %s", key)
				require.Equal(t, ef.Mode, sf.Mode, "Mode mismatch for %s", key)
				require.Equal(t, ef.Size, sf.Size, "Size mismatch for %s", key)

				// Content/ContentSource invariants
				require.Nil(t, sf.Content, "streaming loader must not populate Content for %s", key)
				require.NotNil(t, sf.ContentSource, "streaming loader must set ContentSource for %s", key)

				// Content equality via Open()
				erc, err := ef.Open()
				require.NoError(t, err)
				eBytes, err := io.ReadAll(erc)
				_ = erc.Close()
				require.NoError(t, err)

				src, err := sf.Open()
				require.NoError(t, err)
				sBytes, err := io.ReadAll(src)
				_ = src.Close()
				require.NoError(t, err)

				require.Equal(t, eBytes, sBytes, "file content must match for %s", key)
			}
		})
	}
}

// TestOpenFromDirectory_RandomAccess verifies that files can be opened in any
// order and that opening the same file twice yields independent, correct readers.
func TestOpenFromDirectory_RandomAccess(t *testing.T) {
	a, err := OpenFromDirectory("testdata/sample-agent-v2")
	require.NoError(t, err)
	require.NotEmpty(t, a.Files, "sample-agent-v2 must have at least one file")

	// Iterate in reverse order to exercise out-of-declaration-order access
	for i := len(a.Files) - 1; i >= 0; i-- {
		f := &a.Files[i]

		rc1, err := f.Open()
		require.NoError(t, err)
		data1, err := io.ReadAll(rc1)
		_ = rc1.Close()
		require.NoError(t, err)

		// Second open of the same file must return a new, independent reader
		rc2, err := f.Open()
		require.NoError(t, err)
		data2, err := io.ReadAll(rc2)
		_ = rc2.Close()
		require.NoError(t, err)

		require.Equal(t, data1, data2,
			"repeated reads of %s/%s must return identical bytes",
			f.Target, f.RelativePath)
	}
}

// TestOpenFromDirectory_SymlinkEscape verifies that a symlink pointing outside
// the artifact directory is caught at enumeration time on the streaming path,
// matching the behaviour of the eager loader.
func TestOpenFromDirectory_SymlinkEscape(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"),
		[]byte(minimalMixinYAML), 0o644))

	homeDir := filepath.Join(dir, "files", "home")
	require.NoError(t, os.MkdirAll(homeDir, 0o755))

	outside := filepath.Join(t.TempDir(), "secret.txt")
	require.NoError(t, os.WriteFile(outside, []byte("secret"), 0o644))
	require.NoError(t, os.Symlink(outside, filepath.Join(homeDir, "escaped")))

	_, err := OpenFromDirectory(dir)
	require.ErrorContains(t, err, "escapes the artifact directory",
		"symlink escape must be caught at enumeration time")
}

// TestOpenFromDirectory_EmptyFile exercises empty-file handling on both the
// eager and streaming paths.
func TestOpenFromDirectory_EmptyFile(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"),
		[]byte(minimalMixinYAML), 0o644))

	homeDir := filepath.Join(dir, "files", "home")
	require.NoError(t, os.MkdirAll(homeDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(homeDir, "empty.txt"), []byte{}, 0o644))

	t.Run("eager", func(t *testing.T) {
		a, err := LoadFromDirectory(dir)
		require.NoError(t, err)
		require.Len(t, a.Files, 1)
		require.NotNil(t, a.Files[0].Content, "eager: Content must be non-nil even for empty files")
		require.Empty(t, a.Files[0].Content)

		rc, err := a.Files[0].Open()
		require.NoError(t, err)
		data, err := io.ReadAll(rc)
		_ = rc.Close()
		require.NoError(t, err)
		require.Empty(t, data, "open of empty file must yield zero bytes")
	})

	t.Run("streaming", func(t *testing.T) {
		a, err := OpenFromDirectory(dir)
		require.NoError(t, err)
		require.Len(t, a.Files, 1)
		require.Nil(t, a.Files[0].Content, "streaming: Content must be nil")
		require.NotNil(t, a.Files[0].ContentSource, "streaming: ContentSource must be non-nil")

		rc, err := a.Files[0].Open()
		require.NoError(t, err)
		data, err := io.ReadAll(rc)
		_ = rc.Close()
		require.NoError(t, err)
		require.Empty(t, data, "open of empty streamed file must yield zero bytes")
	})
}

// TestOpenFromDirectory_ErrorPaths exercises the error paths on the streaming
// loader: missing directory and non-directory path.
func TestOpenFromDirectory_ErrorPaths(t *testing.T) {
	t.Run("missing_directory", func(t *testing.T) {
		_, err := OpenFromDirectory("testdata/does-not-exist")
		require.Error(t, err)
	})

	t.Run("not_a_directory", func(t *testing.T) {
		_, err := OpenFromDirectory("testdata/sample-mixin/spec.yaml")
		require.ErrorContains(t, err, "not a directory")
	})
}

// TestOpenFromFS_ErrorPaths covers the error cases for OpenFromFS: a missing
// sub-directory is silently skipped (no files returned), and a missing spec.yaml
// causes an error.
func TestOpenFromFS_ErrorPaths(t *testing.T) {
	t.Run("missing_spec_yaml", func(t *testing.T) {
		fsys := fstest.MapFS{
			"mykit/files/home/file.txt": &fstest.MapFile{Data: []byte("hi")},
		}
		_, err := OpenFromFS(fsys, "mykit")
		require.Error(t, err, "missing spec.yaml must return an error")
	})

	t.Run("missing_files_subdir_is_ok", func(t *testing.T) {
		// files/home and files/workspace are optional; no files is valid.
		fsys := fstest.MapFS{
			"mykit/spec.yaml": &fstest.MapFile{Data: []byte(minimalMixinYAML)},
		}
		a, err := OpenFromFS(fsys, "mykit")
		require.NoError(t, err)
		require.Empty(t, a.Files, "no files/ directory means zero ArtifactFiles")
	})
}

// TestOpenFromFS_Parity asserts that OpenFromFS and LoadFromFS produce the
// same metadata and bytes for every file across MapFS, os.DirFS, and
// single-file cases.
func TestOpenFromFS_Parity(t *testing.T) {
	t.Run("mapfs", func(t *testing.T) {
		fsys := fstest.MapFS{
			"mykit/spec.yaml": &fstest.MapFile{
				Data: []byte(`schemaVersion: "1"
kind: mixin
name: fs-kit-streaming
displayName: FS Kit Streaming
description: "loaded from fs.FS via OpenFromFS"
`),
			},
			"mykit/files/home/hello.txt": &fstest.MapFile{
				Data: []byte("hello from fs"),
				Mode: 0o644,
			},
			"mykit/files/workspace/work.txt": &fstest.MapFile{
				Data: []byte("workspace content"),
				Mode: 0o600,
			},
		}

		eager, err := LoadFromFS(fsys, "mykit")
		require.NoError(t, err)

		streaming, err := OpenFromFS(fsys, "mykit")
		require.NoError(t, err)

		require.Equal(t, eager.Manifest.Name, streaming.Manifest.Name)
		require.Len(t, streaming.Files, len(eager.Files))

		eagerMap := make(map[string]ArtifactFile, len(eager.Files))
		for _, f := range eager.Files {
			eagerMap[f.Target+"/"+f.RelativePath] = f
		}

		for i := range streaming.Files {
			sf := &streaming.Files[i]
			key := sf.Target + "/" + sf.RelativePath
			ef, ok := eagerMap[key]
			require.True(t, ok, "streaming file %q not found in eager result", key)

			require.Equal(t, ef.RelativePath, sf.RelativePath)
			require.Equal(t, ef.Target, sf.Target)
			require.Equal(t, ef.Size, sf.Size, "Size mismatch for %s", key)
			require.Nil(t, sf.Content, "streaming: Content must be nil for %s", key)
			require.NotNil(t, sf.ContentSource, "streaming: ContentSource must be set for %s", key)

			src, err := sf.Open()
			require.NoError(t, err)
			sBytes, err := io.ReadAll(src)
			_ = src.Close()
			require.NoError(t, err)
			require.Equal(t, ef.Content, sBytes, "content must match for %s", key)
		}
	})

	t.Run("os_dirfs", func(t *testing.T) {
		fsys := os.DirFS("testdata")
		streaming, err := OpenFromFS(fsys, "sample-mixin")
		require.NoError(t, err)
		require.NotEmpty(t, streaming.Files)

		eager, err := LoadFromFS(fsys, "sample-mixin")
		require.NoError(t, err)
		require.Equal(t, len(eager.Files), len(streaming.Files))

		for i := range streaming.Files {
			sf := &streaming.Files[i]
			require.Nil(t, sf.Content)
			require.NotNil(t, sf.ContentSource)

			rc, err := sf.Open()
			require.NoError(t, err)
			got, err := io.ReadAll(rc)
			_ = rc.Close()
			require.NoError(t, err)

			require.Equal(t, eager.Files[i].Content, got,
				"os.DirFS stream content must match eager for %s/%s",
				sf.Target, sf.RelativePath)
		}
	})
}

// TestArtifact_Materialize covers all four Materialize scenarios from the
// build spec: streamed→Content populated, eager→no-op, missing-source→error,
// and idempotent.
func TestArtifact_Materialize(t *testing.T) {
	t.Run("streamed_to_eager", func(t *testing.T) {
		a, err := OpenFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)
		require.NotEmpty(t, a.Files)

		// Pre-condition: Content is nil, ContentSource is non-nil
		for i := range a.Files {
			require.Nil(t, a.Files[i].Content)
			require.NotNil(t, a.Files[i].ContentSource)
		}

		require.NoError(t, a.Materialize())

		for i := range a.Files {
			f := &a.Files[i]
			require.NotNil(t, f.Content, "after Materialize, Content must be non-nil")
			require.Equal(t, int64(len(f.Content)), f.Size, "Size must equal len(Content)")
			require.Nil(t, f.ContentSource, "after Materialize, ContentSource must be cleared")
		}
	})

	t.Run("eager_noop", func(t *testing.T) {
		a, err := LoadFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)

		// Snapshot original content slices
		origContent := make([][]byte, len(a.Files))
		for i, f := range a.Files {
			origContent[i] = f.Content
		}

		require.NoError(t, a.Materialize())

		for i, f := range a.Files {
			require.Equal(t, origContent[i], f.Content,
				"Materialize must not change already-eager Content")
		}
	})

	t.Run("missing_source_error", func(t *testing.T) {
		a := &Artifact{
			Files: []ArtifactFile{
				{RelativePath: "missing.txt", Target: TargetHome},
			},
		}
		require.Error(t, a.Materialize(),
			"Materialize must error when a file has neither Content nor ContentSource")
	})

	t.Run("idempotent", func(t *testing.T) {
		a, err := OpenFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)

		require.NoError(t, a.Materialize())
		// Capture content after first Materialize
		snap := make([][]byte, len(a.Files))
		for i, f := range a.Files {
			cp := make([]byte, len(f.Content))
			copy(cp, f.Content)
			snap[i] = cp
		}

		// Second call must be a no-op
		require.NoError(t, a.Materialize())
		for i, f := range a.Files {
			require.Equal(t, snap[i], f.Content,
				"second Materialize must not alter Content")
		}
	})

	t.Run("content_equals_eager", func(t *testing.T) {
		eager, err := LoadFromDirectory("testdata/sample-agent-v2")
		require.NoError(t, err)

		streaming, err := OpenFromDirectory("testdata/sample-agent-v2")
		require.NoError(t, err)
		require.NoError(t, streaming.Materialize())

		eagerMap := make(map[string][]byte, len(eager.Files))
		for _, f := range eager.Files {
			eagerMap[f.Target+"/"+f.RelativePath] = f.Content
		}

		for _, sf := range streaming.Files {
			key := sf.Target + "/" + sf.RelativePath
			ec, ok := eagerMap[key]
			require.True(t, ok, "materialized file %q not in eager result", key)
			require.Equal(t, ec, sf.Content,
				"materialized content must equal eager content for %s", key)
		}
	})
}

// TestArtifactFile_JSONSafety guards simonferquel's concern: json.Marshal of
// an Artifact with non-nil ContentSource must succeed (ContentSource is
// json:"-") and must omit the field; after Materialize a JSON round-trip
// preserves Content.
func TestArtifactFile_JSONSafety(t *testing.T) {
	t.Run("marshal_with_content_source_succeeds", func(t *testing.T) {
		a, err := OpenFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)
		require.NotEmpty(t, a.Files)
		require.NotNil(t, a.Files[0].ContentSource,
			"pre-condition: streaming artifact must have ContentSource")

		data, err := json.Marshal(a)
		require.NoError(t, err, "json.Marshal of artifact with ContentSource must succeed")

		// ContentSource must be absent from the JSON
		require.NotContains(t, string(data), "contentSource")
		require.NotContains(t, string(data), "ContentSource")
	})

	t.Run("json_roundtrip_after_materialize", func(t *testing.T) {
		a, err := OpenFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)
		require.NoError(t, a.Materialize())

		data, err := json.Marshal(a)
		require.NoError(t, err)

		var rt Artifact
		require.NoError(t, json.Unmarshal(data, &rt))

		require.Len(t, rt.Files, len(a.Files))
		for i, f := range a.Files {
			require.Equal(t, f.Content, rt.Files[i].Content,
				"JSON round-trip must preserve Content for file %d", i)
			require.Equal(t, f.RelativePath, rt.Files[i].RelativePath)
			require.Equal(t, f.Target, rt.Files[i].Target)
			require.Equal(t, f.Size, rt.Files[i].Size)
		}
	})
}

// TestValidateArtifact_StreamingLoaded asserts that ValidateArtifact passes
// on streaming-loaded artifacts the same as on eager ones — the validator
// only inspects metadata fields, never Content.
func TestValidateArtifact_StreamingLoaded(t *testing.T) {
	for _, dir := range []string{
		"testdata/sample-mixin",
		"testdata/sample-agent",
		"testdata/sample-agent-v2",
	} {
		dir := dir
		t.Run(dir, func(t *testing.T) {
			a, err := OpenFromDirectory(dir)
			require.NoError(t, err)
			require.NoError(t, ValidateArtifact(a),
				"ValidateArtifact must pass for streaming-loaded artifact from %s", dir)
		})
	}
}

// TestLoadFromDirectory_SizeEqualsContentLen guards the invariant
// Size == len(Content) on the eager directory path. A previous version set
// Size from a pre-enumeration stat call, which could diverge from Content if
// the file changed between stat and ReadFile; we now set it from len(data).
func TestLoadFromDirectory_SizeEqualsContentLen(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"),
		[]byte(minimalMixinYAML), 0o644))

	homeDir := filepath.Join(dir, "files", "home")
	require.NoError(t, os.MkdirAll(homeDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(homeDir, "hello.txt"),
		[]byte("hello world"), 0o644))

	a, err := LoadFromDirectory(dir)
	require.NoError(t, err)
	require.NotEmpty(t, a.Files)
	for _, f := range a.Files {
		require.Equal(t, int64(len(f.Content)), f.Size,
			"eager loader: Size must equal len(Content) for %s/%s",
			f.Target, f.RelativePath)
	}
}

// TestOpenFromDirectory_CWDIndependence guards that ContentSource closures
// produced by OpenFromDirectory remain valid after the process changes its
// working directory. A previous version stored the non-absolute realPath
// from filepath.EvalSymlinks, making opens CWD-dependent.
func TestOpenFromDirectory_CWDIndependence(t *testing.T) {
	artDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(artDir, "spec.yaml"),
		[]byte(minimalMixinYAML), 0o644))

	homeDir := filepath.Join(artDir, "files", "home")
	require.NoError(t, os.MkdirAll(homeDir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(homeDir, "data.txt"),
		[]byte("cwd test"), 0o644))

	// Save current working directory so we can restore it.
	origWD, err := os.Getwd()
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.Chdir(origWD) })

	// Change into artDir so that a relative path of "." is valid.
	require.NoError(t, os.Chdir(artDir))
	a, err := OpenFromDirectory(".")
	require.NoError(t, err)
	require.Len(t, a.Files, 1)

	// Now move the process to a completely different directory so that a
	// relative path stored in the closure would silently resolve to the
	// wrong place or fail.
	require.NoError(t, os.Chdir(t.TempDir()))

	rc, err := a.Files[0].Open()
	require.NoError(t, err, "Open must work after CWD change")
	got, err := io.ReadAll(rc)
	_ = rc.Close()
	require.NoError(t, err)
	require.Equal(t, []byte("cwd test"), got,
		"ContentSource must open the correct file regardless of current CWD")
}

// lyingSizeFS wraps a MapFS and reports a fabricated FileInfo.Size() for
// specific paths, letting tests exercise loaders with an fs.FS whose
// declared size diverges from the actual byte count.
type lyingSizeFS struct {
	fstest.MapFS
	lie map[string]int64 // path -> fake size
}

func (l lyingSizeFS) ReadDir(name string) ([]fs.DirEntry, error) {
	ents, err := l.MapFS.ReadDir(name)
	if err != nil {
		return nil, err
	}
	out := make([]fs.DirEntry, len(ents))
	for i, e := range ents {
		p := path.Join(name, e.Name())
		if sz, ok := l.lie[p]; ok {
			out[i] = lyingDirEntry{DirEntry: e, size: sz}
		} else {
			out[i] = e
		}
	}
	return out, nil
}

type lyingDirEntry struct {
	fs.DirEntry
	size int64
}

func (e lyingDirEntry) Info() (fs.FileInfo, error) {
	info, err := e.DirEntry.Info()
	if err != nil {
		return nil, err
	}
	return lyingFileInfo{FileInfo: info, size: e.size}, nil
}

type lyingFileInfo struct {
	fs.FileInfo
	size int64
}

func (i lyingFileInfo) Size() int64 { return i.size }

// TestOpenFromFS_SizeMatchesLoadFromFS verifies that LoadFromFS and
// OpenFromFS report the same Size for each file, even when the underlying
// fs.FS reports a FileInfo.Size() that differs from the actual byte count.
// Both loaders take Size from FileInfo.Size() (the enumerated e.size) so
// callers see consistent metadata regardless of which loader they use.
func TestOpenFromFS_SizeMatchesLoadFromFS(t *testing.T) {
	const content = "hello from fs" // 13 bytes
	fsys := lyingSizeFS{
		MapFS: fstest.MapFS{
			"mykit/spec.yaml":            {Data: []byte(minimalMixinYAML)},
			"mykit/files/home/hello.txt": {Data: []byte(content), Mode: 0o644},
		},
		lie: map[string]int64{"mykit/files/home/hello.txt": 9999},
	}

	eager, err := LoadFromFS(fsys, "mykit")
	require.NoError(t, err)
	require.Len(t, eager.Files, 1)

	streaming, err := OpenFromFS(fsys, "mykit")
	require.NoError(t, err)
	require.Len(t, streaming.Files, 1)

	require.Equal(t, eager.Files[0].Size, streaming.Files[0].Size,
		"LoadFromFS and OpenFromFS must report the same Size for the same file")
}

// TestMaterialize_PartialFailureIsAtomic ensures that Materialize does not
// leave the artifact in a half-eager state when a mid-loop read fails. A
// caller that marshals the artifact after a failed Materialize must not
// silently lose already-read file bytes as "content": null.
func TestMaterialize_PartialFailureIsAtomic(t *testing.T) {
	a := &Artifact{
		Files: []ArtifactFile{
			{
				RelativePath: "a.txt",
				Target:       TargetHome,
				ContentSource: func() (io.ReadCloser, error) {
					return io.NopCloser(bytes.NewReader([]byte("first"))), nil
				},
			},
			{
				RelativePath: "b.txt",
				Target:       TargetHome,
				ContentSource: func() (io.ReadCloser, error) {
					return nil, errors.New("backing file vanished after enumeration")
				},
			},
		},
	}

	require.Error(t, a.Materialize())

	// No file may be left eager: if a.txt were committed and b.txt were not,
	// a subsequent json.Marshal would emit a.txt's bytes but b.txt as
	// "content":null, silently dropping b.txt's payload with no error.
	require.Nil(t, a.Files[0].Content,
		"a.txt must not be left eager after a failed Materialize (atomicity)")
	require.Nil(t, a.Files[1].Content,
		"b.txt must remain streaming after the error it caused")
}
