# OmO Senpi

This sandbox boots the `pi` agent with the OmO Native CLI installed as `omo`.

- Run `pi` as usual. Its authentication comes from the sandbox proxy; never write
  a real API key into `~/.pi/agent/auth.json` or anywhere in the sandbox.
- `omo` is on `PATH` through `/usr/local/bin/omo`. Use `omo --help` to discover
  its commands; it is the OmO Native entry point, not a second agent.
- Keep secrets on the host. Store an Anthropic credential with
  `sbx secret set anthropic`, or sign in on the host, and recreate the sandbox
  after changing a binding.
- OmO update checks reach `get.omo.dev`. Everything else the agent needs is
  already in the image; do not install a second `pi` or a second Node runtime.
