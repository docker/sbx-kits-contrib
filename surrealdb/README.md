# surrealdb - embedded multi-model SurrealDB (Docker Model Runner)

A mixin kit that adds an **embedded**, multi-model [SurrealDB](https://surrealdb.com/) (documents, graph edges, and native vector search) plus the `surrealdb` Python SDK to any agent sandbox. Vector search is pre-wired to a local [Docker Model Runner](https://docs.docker.com/ai/model-runner/) embedder: no cloud credentials, no separate database server.

The database runs in-process from the Python SDK's bundled storage engines, persisting on disk at `~/.surrealdb/data` (surrealkv). Pairs with any base agent.

## Prerequisites

Docker Model Runner enabled on the host, serving the embedder this kit points at:

```console
docker model pull ai/mxbai-embed-large
```

DMR is reached at `host.docker.internal:12434`; the kit sets `NO_PROXY` so that traffic bypasses the sandbox proxy.

## Usage

```console
sbx run --kit "docker.io/sbx/surrealdb-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=surrealdb" claude
sbx run --kit ./surrealdb/ claude
```

Inside the sandbox:

```python
from surrealdb import Surreal
db = Surreal("surrealkv:///home/agent/.surrealdb/data")
db.connect()
db.use("sandbox", "memory")     # embedded needs no signin
```

One database gives you documents, graph edges (`RELATE a->edge->b`), and native vector search. For semantic memory, embed text with the local DMR embedder and store the vector alongside the text, then query it with SurrealDB's KNN operator.

## What it installs

1. **`surrealdb==2.0.0`** (Python SDK, with embedded storage engines bundled) plus **`openai>=1.0`** (used to call the DMR embedder).
2. **`~/.surrealdb/config.json`** (written only if missing, so it stays editable): the connection (`surrealkv://…/.surrealdb/data`, namespace `sandbox`, database `memory`) and the embedder (`ai/mxbai-embed-large` on DMR, 1024 dims).

## Runbooks

`~/runbooks/` ships runnable demos:

```console
python3 ~/runbooks/travel.py     # vector memory (embed + KNN search)
python3 ~/runbooks/graph.py      # multi-model graph queries
```

## Other embedder backends

This kit uses Docker Model Runner, so it needs no cloud key. If you want the embedder backed by a hosted provider instead, sibling kits carry the different egress, env, and config:

- **`surrealdb-openai`** - OpenAI embeddings (`sbx secret set -g openai`).
- **`surrealdb-gemini`** - Google Gemini embeddings (`sbx secret set -g google`).
