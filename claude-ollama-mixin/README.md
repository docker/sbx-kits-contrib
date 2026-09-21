# claude-ollama-mixin

The Ollama wiring from [`claude-ollama`](../claude-ollama) as a **mixin**
(`kind: mixin`, `schemaVersion: "3"`): it adds the `claude-ollama` wrapper, the
local endpoint's egress, and the model variable to a sandbox that already carries
Claude Code, instead of being the whole environment.

## Composing it

```console
sbx run --kit ./claude-mixin/ --kit ./claude-ollama-mixin/ <base-agent>
```

It declares `requires: ["claude"]`, so the composition must include something
that provides `claude` — either [`claude-mixin`](../claude-mixin) or a base that
already ships the binary. The workload shape gets `claude` from its
`docker/sandbox-templates:claude-code-docker` base and re-pins it to an exact
release; a mixin cannot bring a base, so it states the requirement instead.

That is also why this is the one kit in the family whose `provides` stays
unversioned. [`claude-ollama`](../claude-ollama) publishes
`claude-ollama@<Claude Code version>` because it ships the binary behind the
wrapper. This overlay ships one `export` and no binary at all, so a version here
would be a claim about the base's content, wrong on every base carrying a
different release. Constrain `claude` — the name the base actually provides —
rather than `claude-ollama`.

## Usage inside the sandbox

Run `claude-ollama` rather than `claude`. The wrapper exports
`ANTHROPIC_BASE_URL=http://host.docker.internal:11434`, unsets
`ANTHROPIC_API_KEY`, pins every model alias to `$CLAUDE_OLLAMA_MODEL`
(default `gemma4:e4b-it-q4_K_M`), and then execs `claude`.

To use a different model, override `CLAUDE_OLLAMA_MODEL` per sandbox, or change
the default in `claude-ollama-mixin.dockerfile` in a fork.

## What it deliberately leaves to the base workload

| Left out | Why |
|---|---|
| `ENTRYPOINT` | The base's launch command stays; you run `claude-ollama` yourself. In the workload shape the wrapper *is* the entrypoint. |
| `sbx@1` | A mixin's image config is not the composed image's. |
| `agent-sessions@1` | The recorded `prompt` verb is an argv tail on a launch command this kit does not own. |
| `agent-context` `filename:` | `CLAUDE.md` names the profile, which belongs to the workload. |
| `CLAUDE_OLLAMA_MODEL` as image `ENV` | A mixin's `ENV` does not become the composed image's, so it rides the overlay as a `/etc/profile.d/claude-ollama-env.sh` export. |

## One thing to know about egress

Allow-lists union per phase across a composition. Pairing this with
[`claude-mixin`](../claude-mixin) keeps that kit's Anthropic hosts reachable
alongside the local endpoint — the wrapper still routes Claude Code at Ollama,
but "Anthropic's API is not reachable" stops being true of the sandbox as a
whole. The [`claude-ollama`](../claude-ollama) workload, which declares the local
endpoint and nothing else, is the shape that holds that property.
