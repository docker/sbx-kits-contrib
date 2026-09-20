# Google Antigravity

This sandbox runs Google's Antigravity agent as `agy`. Authentication has two
modes and the sandbox picks between them for you: with a Google credential
bound, `GEMINI_API_KEY` carries a sentinel the egress proxy swaps for the real
key at Google's endpoints, and a startup hook sets `modelProvider: gemini` in
`~/.gemini/antigravity-cli/settings.json`. With nothing bound, that key is
removed and `agy` falls back to its interactive Google sign-in.

Egress is limited to Google's own hosts plus Antigravity's product and
update hosts, so an MCP server or a tool that reaches anywhere else will be
refused by the sandbox rather than by the agent.
