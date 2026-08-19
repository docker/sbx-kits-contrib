# Docker Sandboxes Kit OCI Artifact — v2

Normative reference for how a **`schemaVersion: "2"` kit** is packaged, pushed,
and pulled as an [OCI](https://github.com/opencontainers/image-spec) artifact.
This document covers the *distribution* format only; the `spec.yaml` grammar it
carries is defined in [SPEC-v2.md](SPEC-v2.md).

The format follows the [OCI image-spec](https://github.com/opencontainers/image-spec).
Where this document and a released `sbx` disagree, the running engine wins.

Only v2 is specified here. v1 (the legacy ZIP artifact) is out of scope; it is
mentioned only where a rule exists specifically to keep the two formats
distinguishable.

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, and **MAY** are
used as described in RFC 2119.

---

## 1. Overview

A v2 kit is distributed as a single **OCI image manifest** with three moving
parts:

1. an **`artifactType`** that marks the manifest as a Docker Sandboxes kit;
2. a **config blob** that carries the verbatim `spec.yaml`; and
3. exactly one **tar+gzip layer** that carries the kit's `files/` tree.

Kit identity and standard OCI metadata are additionally mirrored as **manifest
annotations**, so a registry or listing UI can read a kit's name, kind, and
version **without pulling any blob**.

```
                          ┌───────────────────────────────────────────┐
   OCI image manifest  ─► │ mediaType  application/vnd.oci.image      │
   (media type          │ │            .manifest.v1+json              │
   application/vnd.oci  │ │ artifactType application/vnd.docker       │
   .image.manifest      │ │            .sandbox.kit.v2                │
   .v1+json)            │ │ annotations {name, kind, version, title…} │
                          └───────────────┬───────────────┬───────────┘
                                          │               │
                config blob ◄─────────────┘               └────────► layer[0]
        application/vnd.docker.sandbox.kit          application/vnd.oci.image
              .v2.spec+yaml                              .layer.v1.tar+gzip
        (the raw spec.yaml bytes)                  (files/ as home/agent/… +
                                                    workspace/… entries)
```

The config blob and the annotations are the reason v2 exists: v1 buried the
spec inside a ZIP layer, so metadata could not be read without downloading the
payload. v2 hoists the spec into the config blob and mirrors identity into
annotations.

---

## 2. Media types

| Role | Media type |
|---|---|
| Manifest | `application/vnd.oci.image.manifest.v1+json` |
| Manifest `artifactType` | `application/vnd.docker.sandbox.kit.v2` |
| Config blob (the `spec.yaml`) | `application/vnd.docker.sandbox.kit.v2.spec+yaml` |
| Payload layer | `application/vnd.oci.image.layer.v1.tar+gzip` |

Notes:

- The manifest is a standard OCI **image** manifest carrying an `artifactType`
  (the OCI image-spec 1.1 pattern), not the deprecated OCI *artifact* manifest.
  The kit-specific type lives in the manifest's `artifactType` field, **not** in
  `mediaType`.
- The payload layer uses the **standard** OCI tar+gzip media type — it is a
  plain layer, deliberately not a bespoke type. v1 used a bespoke ZIP layer
  type (`application/vnd.docker.sandbox.kit.v1.content.zip`); keeping the v2
  layer standard while the v1 layer is bespoke lets a consumer route by layer
  media type alone when `artifactType` is absent (see [§7](#7-consuming-pull)).

---

## 3. Manifest

A conforming v2 kit manifest:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.docker.sandbox.kit.v2",
  "config": {
    "mediaType": "application/vnd.docker.sandbox.kit.v2.spec+yaml",
    "digest": "sha256:…",
    "size": 1234
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:…",
      "size": 5678
    }
  ],
  "annotations": {
    "vnd.docker.sandbox.kit.name": "my-plugin",
    "vnd.docker.sandbox.kit.kind": "mixin",
    "vnd.docker.sandbox.kit.version": "1.0.0",
    "org.opencontainers.image.title": "My Plugin",
    "org.opencontainers.image.description": "Adds the foo toolchain",
    "org.opencontainers.image.source": "https://github.com/myorg/my-plugin",
    "org.opencontainers.image.created": "1970-01-01T00:00:00Z"
  }
}
```

Rules:

- The manifest **MUST** set `artifactType` to
  `application/vnd.docker.sandbox.kit.v2`.
- The manifest `config` **MUST** have media type
  `application/vnd.docker.sandbox.kit.v2.spec+yaml`.
- The manifest **MUST** contain **exactly one** layer of media type
  `application/vnd.oci.image.layer.v1.tar+gzip`. More than one is an error.
- The manifest **MAY** carry additional layers of *other* media types (e.g.
  signatures or attestations); a consumer **MUST** ignore layers it does not
  recognize rather than fail.

### 3.1 Config blob — the `spec.yaml`

- The config blob **MUST** be the **verbatim bytes** of the kit's `spec.yaml`
  (or `spec.yml`), exactly as read from disk.
- A producer **MUST NOT** re-serialize the spec: round-tripping through a YAML
  encoder would discard author comments and reorder fields, changing the blob
  digest for a semantically identical kit and breaking registry deduplication.
- The blob's schema is [SPEC-v2.md](SPEC-v2.md); a consumer parses it with the
  v2 loader. The declared `schemaVersion` inside the blob **MUST** be `"2"`.

### 3.2 Annotations

| Key | Presence | Value |
|---|---|---|
| `vnd.docker.sandbox.kit.name` | REQUIRED | Kit `name`. |
| `vnd.docker.sandbox.kit.kind` | REQUIRED | Kit `kind`: `sandbox` or `mixin`. |
| `vnd.docker.sandbox.kit.version` | optional | Kit `version`, when set. |
| `org.opencontainers.image.title` | REQUIRED | `displayName`, falling back to `name`. |
| `org.opencontainers.image.description` | optional | Kit `description`, when set. |
| `org.opencontainers.image.source` | optional | Kit `sourceURL`, when set. |
| `org.opencontainers.image.created` | REQUIRED | RFC 3339 timestamp (set by the packer). |

Annotations are a **read-optimization mirror** of the spec, not a second source
of truth. A consumer that has pulled and parsed the config blob **MUST** treat
the parsed spec as authoritative if the two ever disagree.

---

## 4. Payload layer

The single tar+gzip layer carries the kit's file tree — and nothing else (the
spec is in the config blob, not the layer).

### 4.1 Entry naming and target routing

The kit's on-disk `files/` subtree is rewritten into two reserved top-level
prefixes that encode the injection target:

| On disk (kit dir) | Tar entry | Injection target |
|---|---|---|
| `files/home/<rel>` | `home/agent/<rel>` | Agent home (`/home/agent/<rel>`) |
| `files/workspace/<rel>` | `workspace/<rel>` | Workspace root |

- Every regular-file entry **MUST** begin with `home/agent/` or `workspace/`.
- The prefix is the **only** signal a consumer uses to decide where a file is
  injected; there is no separate manifest field for per-file targets.
- Both subtrees are optional. A kit with neither (a pure behavioral mixin, e.g.
  network + credentials only) produces a valid **empty** layer.

### 4.2 Entry constraints

A conforming layer:

- **MUST** contain only regular files and directory entries. Symlinks,
  hardlinks, devices, FIFOs, and any other type **MUST** be rejected by both
  producer and consumer.
- Entry paths **MUST** be relative and normalized. Absolute paths and any path
  that is not equal to its cleaned form (e.g. containing `..`) **MUST** be
  rejected — this closes path-escape attacks before the prefix check runs.
- Directory entries carry no payload and **MAY** be omitted; a consumer
  reconstructs the directory tree from the regular-file paths and **MUST NOT**
  require explicit directory entries.
- An entry whose relative path is empty after stripping its prefix (i.e. the
  bare prefix itself) **MUST** be rejected.

### 4.3 Reproducibility (content-addressable layers)

To make the layer bytes deterministic — identical inputs yield an identical
digest, so registries deduplicate and pulls cache-hit — a producer **MUST**
pin the following and ignore the on-disk values:

| Field | Pinned value |
|---|---|
| File mode | `0644` for every regular file |
| uid / gid | `1000` / `1000` |
| mtime | Unix epoch (`1970-01-01T00:00:00Z`) |
| gzip header | zeroed (no embedded mtime or OS byte) |

Consequences:

- Per-file executable bits are **not** representable in a v2 layer. A kit that
  needs an executable file must arrange it another way (e.g. a `setup` step that
  `chmod`s after injection), not by relying on the on-disk mode.
- A consumer **MUST** mask any incoming mode to its permission bits (`0o777`)
  and **MUST NOT** honor setuid/setgid/sticky bits. A masked mode of `0`
  **SHOULD** be treated as `0644` so an injected file is never unreadable.

---

## 5. Reference and tagging

- A kit is pushed to a normal OCI reference: `registry/repo:tag`
  (e.g. `ghcr.io/myorg/my-plugin:1.0`) or by digest
  (`registry/repo@sha256:…`).
- Authentication uses the Docker credential store.
- There is no required relationship between the reference tag and the kit's
  `version` field, though publishers **SHOULD** keep them aligned.

---

## 6. Producing (push)

Given a kit directory with a `schemaVersion: "2"` `spec.yaml`, a conforming
producer:

1. **Loads and validates** the kit (spec + `files/`). An invalid kit **MUST
   NOT** be pushed.
2. **Packs the layer**: walks `files/home/` and `files/workspace/`, emitting the
   prefixed, pinned tar entries of [§4](#4-payload-layer), gzip-compresses the
   result, and computes its `sha256` descriptor.
3. **Pushes the config blob** = the raw `spec.yaml` bytes, media type
   `application/vnd.docker.sandbox.kit.v2.spec+yaml`.
4. **Pushes the layer** blob.
5. **Assembles the manifest** with `artifactType`
   `application/vnd.docker.sandbox.kit.v2`, the config descriptor, the single
   layer, and the annotations of [§3.2](#32-annotations).
6. **Tags** the manifest with the target reference.

A producer **SHOULD** stream the layer to temporary storage while hashing in a
single pass rather than buffering the whole archive in memory.

---

## 7. Consuming (pull)

A conforming consumer:

1. Fetches and **digest-verifies** the manifest.
2. Determines the format from `artifactType`:
   - `application/vnd.docker.sandbox.kit.v2` ⇒ v2.
   - If `artifactType` is **absent** (some registries strip it), the consumer
     **MAY** fall back to a **fingerprint**: a config media type of
     `application/vnd.docker.sandbox.kit.v2.spec+yaml` identifies v2. A plain
     OCI image (ordinary config/layer types) **MUST NOT** be misidentified as a
     kit.
3. Fetches and digest-verifies the **config blob** and parses it with the v2
   spec loader.
4. Selects the **single** `application/vnd.oci.image.layer.v1.tar+gzip` layer.
   Zero such layers, or more than one, **MUST** be an error.
5. Streams the layer, **verifying its OCI digest before use**, decompresses it,
   and routes each entry to its target by prefix ([§4.1](#41-entry-naming-and-target-routing)).
6. **Validates** the fully assembled artifact (manifest + files) before the kit
   is used, applying the same validation a kit loaded from a local directory
   receives.

Consumers **SHOULD** cache the decompressed layer keyed by its layer digest so
repeated pulls of the same kit skip download and decompression. File content
**SHOULD** be readable on demand (seek-on-open) rather than held fully in
memory.

---

## 8. Relationship to v1

Out of scope here, with one intentional touch-point: the v2 payload layer uses
the **standard** `application/vnd.oci.image.layer.v1.tar+gzip` type while v1
uses a **bespoke** `application/vnd.docker.sandbox.kit.v1.content.zip` layer and
an empty config. That difference is what lets a consumer route by layer media
type alone when a registry has stripped `artifactType`. New kits **SHOULD**
target v2.

---

## 9. Conformance checklist

A v2 kit artifact is conforming when:

- [ ] Manifest `artifactType` is `application/vnd.docker.sandbox.kit.v2`.
- [ ] `config.mediaType` is `application/vnd.docker.sandbox.kit.v2.spec+yaml`
      and the blob is the verbatim `spec.yaml` (declaring `schemaVersion: "2"`).
- [ ] Exactly one `application/vnd.oci.image.layer.v1.tar+gzip` layer is present.
- [ ] Every layer file entry is a normalized, relative, regular file under
      `home/agent/` or `workspace/`.
- [ ] Layer entries are mode `0644`, uid/gid `1000`, mtime epoch; the gzip
      header is zeroed.
- [ ] Required annotations `vnd.docker.sandbox.kit.name`,
      `vnd.docker.sandbox.kit.kind`, and `org.opencontainers.image.title` are
      present.
