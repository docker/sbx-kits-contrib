# `claude-connectors` — sbx mixin kit

A ~10-line `sbx` mixin kit that enables claude.ai-hosted MCP connectors
(Slack, Gmail, Notion, Atlassian, etc.) inside an sbx-sandboxed Claude Code
by allowing `mcp-proxy.anthropic.com` through the sandbox network policy.

Status: **working fix**, opt-in. Belongs upstream in the base `claude` kit
in `docker/sandboxes` (filing as a follow-up).

---

## What it does

| Kit primitive | Effect |
|---|---|
| `network.allowedDomains: mcp-proxy.anthropic.com:443` | Lets the sandbox's egress proxy reach the connector dispatch host. |
| `network.serviceDomains: mcp-proxy.anthropic.com: anthropic` | Binds it to the existing `anthropic` service so the OAuth sentinel-swap applies. |

That's it. No startup commands, no env vars, no file overlays. Just the
network policy gap that the base `claude` kit is missing.

### Why a runtime `sbx policy allow network` is not enough

The obvious one-liner fix —

```bash
sbx policy allow network <sandbox> "mcp-proxy.anthropic.com:443"
```

— **does not work.** Verified. That command is the runtime equivalent of
`allowedDomains` only; it punches a hole in the egress firewall but does
not bind the host to a `serviceDomains` entry. Without the binding, the
proxy does not engage the OAuth sentinel-swap for traffic to
`mcp-proxy.anthropic.com`, so the sandbox's `Authorization: Bearer
sk-ant-oat01-proxy-managed` reaches Anthropic literally and is rejected.
The connector dispatch still fails, even though the host is now reachable.

Both lines are required. `serviceDomains` is a **composition-only**
concept — it can only be supplied through a kit (or the base agent kit)
and is applied at sandbox creation. The `sbx policy` surface exposes only
`allow network` / `deny network` / `set-default` for hosts, and no
imperative equivalent exists for binding a host to a service in the
sentinel-swap map. Once a sandbox is running, the binding is fixed. That
is why this gap has to be closed at the kit layer rather than with a
runtime policy tweak.

---

## Why this is needed

In a stock sbx-sandboxed Claude Code (`sbx create … claude`), every
claude.ai connector — `mcp__claude_ai_Slack__*`, `Notion`, `Gmail`,
`Atlassian`, etc. — appears in the tool catalog but reports
**"needs authentication"** under `/mcp`. The user's host Claude Code can
invoke the same connectors fine; the sandbox can't.

Re-authenticating inside the sandbox is the wrong answer — the whole point
of sbx is that the agent never holds your credentials.

### Root cause

Claude Code dispatches each connector tool over standard MCP JSON-RPC to
`https://mcp-proxy.anthropic.com/v1/mcp/<server-id>`. Captured from the
host with `mitmproxy`:

```
POST https://mcp-proxy.anthropic.com/v1/mcp/mcpsrv_013gPm2pCFxoChXFY64pfGK4
  Authorization: <redacted, 115 chars>
  User-Agent: claude-code/2.1.150 (sdk-cli)
  X-Mcp-Client-Session-Id: 63237c00-280d-48f0-88d6-7b37bf2097a4
  Content-Type: application/json
  body: {"method":"initialize","params":{...},"jsonrpc":"2.0","id":0}
→ 200 OK  text/event-stream
  data: {"result":{"protocolVersion":"2025-11-25","capabilities":{...}}}
```

The base `claude` kit's network policy in
[docker/sandboxes](https://github.com/docker/sandboxes/blob/main/sandboxlib/kit/agents/claude/spec.yaml):

```yaml
network:
  serviceDomains:
    api.anthropic.com: anthropic
    console.anthropic.com: anthropic
    claude.ai: anthropic
  allowedDomains:
    - "downloads.claude.ai:443"
    - "claude.com:443"
```

`mcp-proxy.anthropic.com` is not in the list. The sandbox's egress proxy
denies the connection; Claude Code reports "needs authentication" as a
generic fallback for connector dispatch failures.

The OAuth session itself is healthy (the connector *list* surfaces correctly
via `api.anthropic.com/v1/mcp_servers`, which is allowed). Only dispatch is
blocked.

---

## Verified end-to-end (2026-06-05, sbx v0.31.3)

```bash
$ sbx kit validate kit/claude-connectors
VALID: kit/claude-connectors (directory)

$ sbx run claude --kit kit/claude-connectors --name connectors-test .
…
✓ Created sandbox 'connectors-test'

# Inside the sandbox: /mcp shows connectors authenticated (not "needs auth"),
# and tool invocations succeed:
$ # (interactive: ask claude "use slack_read_user_profile and tell me what comes back")
# → real Slack profile JSON, dispatched via mcp-proxy.anthropic.com
```

### Secrets-stay-on-host check

The kit binds `mcp-proxy.anthropic.com` to the existing `anthropic` service,
so the host-side proxy's OAuth sentinel-swap applies to those requests too:

```bash
$ sbx exec connectors-test -- sh -c 'cat $HOME/.claude/.credentials.json'
{"claudeAiOauth":{
  "accessToken":"sk-ant-oat01-proxy-managed",
  "refreshToken":"sk-ant-ort01-proxy-managed",
  "expiresAt":…,
  "scopes":["user:file_upload","user:inference","user:mcp_servers",
            "user:profile","user:sessions:claude_code"]}}

$ sbx exec connectors-test -- env | grep -iE "anthropic|claude|api_key|token"
CLAUDE_ENV_FILE=/etc/sandbox-persistent.sh
GH_TOKEN=gho_sbxproxymanaged000000000000000000000
ANTHROPIC_OAUTH_TOKEN=sbx-cs-0YU3dkaSZ8yRS1E2
MCP_SENTINEL_TOKEN_NAME=proxy-managed
```

Both the rendered credentials file and the environment carry sentinel
values only. Real Anthropic OAuth access tokens are `sk-ant-oat01-…`
followed by ~100 chars of base64; the sandbox sees the literal string
`sk-ant-oat01-proxy-managed` and an `sbx-cs-…` credential-service handle.
The host-side proxy substitutes the real token before forwarding to
`mcp-proxy.anthropic.com`.

Notable: the scope list includes `user:mcp_servers`, which is what
authorizes connector dispatch server-side. The base OAuth session already
covers all connectors the user has granted via claude.ai's web UI — there
is no per-connector token to forward, which is why hunting for one on disk
came up empty before mitmproxy revealed the network-policy block.

---

## What this does NOT solve

- **Capability-level gating.** Sentinel-swap protects token *storage*,
  not *spend*. The sandbox can still invoke any connector tool by sending
  a request through the proxy, which transparently swaps the sentinel for
  the real OAuth token. A buggy or malicious agent in the sandbox can
  therefore send Slack messages, read your Gmail, etc. — the credential
  is gated, the capability is not. Same property already holds for plain
  `api.anthropic.com` calls; this kit extends it to connector dispatch.

- **Server-side per-connector authorization.** Whether a given connector
  is dispatchable at all is decided by Anthropic from your OAuth grants
  (`user:mcp_servers` scope + your claude.ai connector grants). The kit
  has no influence on that — the sandbox sees exactly the connector
  catalog your host Claude Code sees.

- **Anthropic protocol stability.** `mcp-proxy.anthropic.com` is not a
  documented API surface. If Anthropic moves connector dispatch to a
  different hostname, the allowlist needs updating.

---

## Upstream ask

The two-line equivalent change belongs in the base `claude` kit at
`sandboxlib/kit/agents/claude/spec.yaml` in
[docker/sandboxes](https://github.com/docker/sandboxes/blob/main/sandboxlib/kit/agents/claude/spec.yaml):

```yaml
network:
  serviceDomains:
    mcp-proxy.anthropic.com: anthropic   # add
  allowedDomains:
    - "mcp-proxy.anthropic.com:443"       # add
```

Once that lands and ships, this mixin can be retired.

---

## Files

- `spec.yaml` — the mixin (~30 lines including comments).
- `README.md` — this file.
