## agentmemory

This sandbox runs a local agentmemory service. Claude Code
and Codex have its MCP server registered as `agentmemory-sbx`. Use
`memory_recall` to recall relevant prior decisions before starting work,
and `memory_save` to save useful facts, preferences, and decisions.
Include the project name when saving or searching. Never save credentials.

The service uses keyword search with no LLM calls and no embedding
downloads. LLM summarization and semantic vector search are off. No
automatic capture hooks are installed, so save memories explicitly through
MCP.

State is written to disk every two seconds and survives a sandbox restart
after that write. Wait a few seconds after the last save before stopping the
sandbox. Removing the sandbox removes its memory too; export anything needed
elsewhere before removal.

Other agents can use the stdio command `agentmemory-sbx mcp` or the loopback
REST API at `http://127.0.0.1:3111/agentmemory`.

Diagnose with `agentmemory-sbx status` and
`/home/agent/.local/share/agentmemory-sbx/startup.log`. Start the service
again with `sh /opt/agentmemory-sbx/start.sh`. If a tool reports a
connection error, report that the memory service is unavailable; do not
claim a memory was saved.
