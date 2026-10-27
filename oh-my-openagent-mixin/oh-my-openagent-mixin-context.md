# OmO Native CLI

The OmO Native CLI is installed as `omo` and is on `PATH` through
`/usr/local/bin/omo`.

- `omo --help` lists its commands. It is not an agent: the sandbox's agent is the
  base workload's, and its launch command is unchanged.
- Anthropic access belongs to the base workload. Do not declare or store another
  credential for it here; store the key on the host with
  `sbx secret set anthropic` and recreate the sandbox.
- OmO update checks reach `get.omo.dev`. If a command needs another host, add it
  to this kit's allow list rather than reaching around the policy.
