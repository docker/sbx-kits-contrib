## Codex app-server over SSH

sshd is running inside the sandbox on port 22, and your host's SSH
identities (from the forwarded agent socket) are pre-populated in
`/home/agent/.ssh/authorized_keys`. The kit requests port 22 through its
port capability, so the runtime exposes sshd on an ephemeral host
port automatically. Discover the assigned port with
`sbx ports <sandbox>`, then add an SSH connection in the Codex Mac
app:

    Host: localhost
    Port: <host-port from sbx ports>
    User: agent

The Codex GUI will SSH in and run `codex app-server` over stdio.
Model traffic continues to route through the codex agent's OpenAI
credential proxy, so no API key lives in the sandbox.
