# qdrant-agent

Mixin kit that adds Qdrant vector search to any sandbox agent via the official
qdrant-client Python SDK running in-process. No external service or Docker
daemon required — collections and vectors live in memory for the duration of
the sandbox session.

## Usage

    sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=qdrant-agent" claude

Swap claude for any other agent — pi, hermes-agent, or your own custom agent.
Unlike database mixins that require Docker-in-Docker, this mixin works on top
of any agent regardless of base image.

## Prerequisites

No external accounts, API keys, or credentials required.

## How it works

qdrant-client ships with a full in-process vector engine. Passing ":memory:"
instead of a host creates a complete Qdrant instance inside the Python process
— same API, same collection semantics, same query behaviour as a production
Qdrant server. No network hop, no container startup, no port conflicts.

The qdrant-client API is identical whether using in-memory or a remote server.
Switching to production requires one line change:

    # Development (this kit)
    _client = QdrantClient(":memory:")

    # Production
    _client = QdrantClient(host="your-qdrant-host", port=6333)

fastembed is included for local embedding generation. The first call to embed()
downloads a model (~40 MB for the default bge-small-en-v1.5) to
~/.cache/fastembed. Subsequent calls use the cached model.

## What is inside the sandbox

    /home/agent/workspace/
    vector.py    # qdrant-client helper — create_collection, upsert, search, embed
    QDRANT.md    # Loaded by the agent on startup

### vector.py

Create a collection:

    from vector import create_collection, upsert, search, embed

    create_collection("documents", vector_size=384, distance="Cosine")

Common vector sizes:
    384  — fastembed bge-small-en-v1.5 (built-in, no API key needed)
    768  — bge-base-en-v1.5, sentence-transformers
    1536 — OpenAI text-embedding-3-small
    3072 — OpenAI text-embedding-3-large

Generate embeddings locally (no API key):

    vectors = embed(["hello world", "goodbye world"])

Upsert points:

    upsert("documents", [
        {"id": 1, "vector": vectors[0], "payload": {"text": "hello world", "category": "greeting"}},
        {"id": 2, "vector": vectors[1], "payload": {"text": "goodbye world", "category": "farewell"}},
    ])

Similarity search:

    results = search("documents", query_vector=vectors[0], limit=5)
    for r in results:
        print(r["score"], r["payload"])

Hybrid search (vector + payload filter):

    results = search(
        "documents",
        query_vector=vectors[0],
        limit=5,
        payload_filter={"category": "greeting"},
    )

Direct qdrant-client access for advanced use:

    from vector import client
    c = client()
    c.get_collections()

## Network policy

The sandbox runs under a deny-all baseline. Domains required:

    pypi.org, files.pythonhosted.org, pythonhosted.org  -- pip installs
    huggingface.co, hf.co, cdn-lfs.hf.co               -- fastembed model downloads
    archive.ubuntu.com, security.ubuntu.com             -- apt (amd64)
    ports.ubuntu.com                                    -- apt (arm64)
    download.docker.com                                 -- Docker apt repo

No Docker Hub domains are needed — Qdrant runs in-process, no container pulled.

## Using a production Qdrant server

Override the client in vector.py before making any calls:

    from qdrant_client import QdrantClient
    import vector
    vector._client = QdrantClient(host="your-qdrant-host", port=6333)
