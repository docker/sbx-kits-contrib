#!/bin/sh
set -u

launcher=/usr/local/bin/agentmemory-sbx
PATH="$HOME/.local/bin:/usr/local/share/npm-global/bin:$PATH"
export PATH
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC

if command -v claude >/dev/null 2>&1; then
  claude mcp get agentmemory-sbx >/dev/null 2>&1 ||
    claude mcp add --scope user agentmemory-sbx -- sh "$launcher" mcp ||
    echo "agentmemory: could not register the MCP server with claude" >&2
fi

if command -v codex >/dev/null 2>&1; then
  codex mcp get agentmemory-sbx >/dev/null 2>&1 ||
    codex mcp add agentmemory-sbx -- sh "$launcher" mcp ||
    echo "agentmemory: could not register the MCP server with codex" >&2
fi

exit 0
