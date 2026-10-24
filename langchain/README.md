# langchain - LangChain / LangGraph

A mixin kit that installs [LangChain](https://github.com/langchain-ai/langchain) and [LangGraph](https://github.com/langchain-ai/langgraph) in an isolated Python virtual environment, so an agent can build and run graph-based LLM workflows inside the sandbox. Proxy-mediated auth for every model provider LangChain's own `init_chat_model("<provider>:<model>")` helper resolves by name.

Pairs with any base agent - this kit adds a Python framework to call out to an LLM provider, rather than being an agent CLI itself.

## Usage

```console
sbx run --kit "docker.io/sbx/langchain-kit:latest" claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=langchain" claude
sbx run --kit ./langchain/ claude
```

## How auth works

The kit declares one credential per provider LangChain names first-class in `init_chat_model`: Anthropic, OpenAI, Google (Gemini), Mistral, Groq, Cohere, DeepSeek, Fireworks, and OpenRouter. None is `required` - set only the ones you actually use:

```console
sbx secret set anthropic
sbx secret set openai
# ... etc, one per provider you want
```

Each credential is `proxyManaged`: the sandbox never sees the real key, only a sentinel environment variable (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, ...) that the sbx proxy overwrites on the wire for the matching provider domain - same mechanism, same credential list shape, as the `crush` kit in this repo. Because the env var names match what each provider's own SDK (and therefore LangChain's integration package) already reads, there is no LangChain-specific config step.

## What it installs

In an isolated venv at `/opt/langchain` (not the system Python, so it can't collide with whatever the base agent needs):

1. **`langchain==0.3.27`** and **`langgraph==0.6.8`**.
2. The matching `langchain-<provider>` integration package for every provider above (`langchain-anthropic`, `langchain-openai`, `langchain-google-genai`, `langchain-mistralai`, `langchain-groq`, `langchain-cohere`, `langchain-fireworks`) - `init_chat_model` imports these lazily by provider name, so they need to already be installed for whichever provider a script picks at runtime.
3. A `langchain-python` shell alias/wrapper pointing at the venv's interpreter, plus `$LANGCHAIN_PYTHON`/`$LANGCHAIN_VENV` for scripting.

## Runbooks

`~/runbooks/hello_graph.py` is a minimal two-node LangGraph app (`StateGraph` with a single `init_chat_model` call) you can run as a smoke test or copy as a starting point:

```console
python3 ~/runbooks/hello_graph.py "explain mixin kits in one sentence"
python3 ~/runbooks/hello_graph.py "explain mixin kits in one sentence" openai:gpt-4o-mini
```

## Cleanup

```console
sbx secret rm -g --service anthropic   # repeat per provider you set
```
