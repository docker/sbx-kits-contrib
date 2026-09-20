# Google Antigravity

Google's Antigravity agent is available in this sandbox as `agy`. Run it from
the shell — this kit is a mixin, so the sandbox's launch command belongs to
whatever workload it was layered onto.

Authentication has two modes and the sandbox picks between them for you: with
a Google credential bound, `GEMINI_API_KEY` carries a sentinel the egress
proxy swaps for the real key at Google's endpoints, and a startup hook sets
`modelProvider: gemini` in `~/.gemini/antigravity-cli/settings.json`. With
nothing bound, that key is removed and `agy` falls back to its interactive
Google sign-in.

Egress is limited to Google's own hosts plus Antigravity's product and update
hosts, so a tool that reaches anywhere else will be refused by the sandbox
rather than by the agent.
