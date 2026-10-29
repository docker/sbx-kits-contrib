# mem0 - Mem0 memory layer (Docker Model Runner)

A mixin kit that adds the [Mem0](https://github.com/mem0ai/mem0) memory layer (`mem0ai`) to any agent sandbox, pre-wired to a local [Docker Model Runner](https://docs.docker.com/ai/model-runner/) (DMR) for both the LLM and the embedder. No cloud credentials, no external vector database: the LLM and embedder run on DMR and the vector store is an on-disk Qdrant inside the sandbox.

Pairs with any base agent (claude, codex, gemini, ...): Mem0 is a Python library the agent (or your own scripts) call, not an agent-specific hook.

## Prerequisites

Docker Model Runner enabled on the host, serving the two models this kit points at:

```console
docker model pull ai/gemma3
docker model pull ai/mxbai-embed-large
```

DMR is reached from the sandbox at `host.docker.internal:12434`; the kit sets `NO_PROXY` so that traffic bypasses the sandbox proxy.

## Usage

```console
sbx run --kit "docker.io/sbx/mem0-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=mem0" claude
sbx run --kit ./mem0/ claude
```

Inside the sandbox, Mem0 works with no further setup:

```python
from mem0 import Memory
m = Memory.from_config(config_path="/home/agent/.mem0/config.json")
m.add("The user prefers dark mode", user_id="u1")
print(m.search("what are the user's preferences?", user_id="u1"))
```

## What it installs

1. **`mem0ai[nlp]==2.0.5`** plus `click`, pinned, via pip.
2. **The spaCy English model** (`en_core_web_sm`) for lemmatization.
3. **`~/.mem0/config.json`** (written only if missing, so it stays editable) wiring Mem0 to:
   - **LLM**: `ai/gemma3` on DMR
   - **Embedder**: `ai/mxbai-embed-large` on DMR (1024 dims)
   - **Vector store**: on-disk Qdrant at `~/.mem0/qdrant`

## Other backends

This kit uses Docker Model Runner, so it needs no cloud key. If you want Mem0 backed by a hosted provider instead, sibling kits carry the different egress, env, and config:

- **`mem0-openai`** - OpenAI for the LLM and embedder (`sbx secret set -g openai`).
- **`mem0-gemini`** - Google Gemini for the LLM and embedder (`sbx secret set -g google`).

Those keys are supplied by the sbx proxy from the stored secret and never enter the sandbox.
