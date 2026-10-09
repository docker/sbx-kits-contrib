# Devin Enterprise

`devin` is an authentication wrapper; `devin-cli` is the underlying CLI.
The wrapper validates existing credentials, clears an empty key before login,
and uses the manual token flow when sign-in is needed.

The sandbox pins enterprise routing in `/etc/devin/system.json`. Credentials
live at `~/.local/share/devin/credentials.toml`, persist across restarts, and
are lost when the sandbox is recreated. Unlike the SaaS Devin kit, the durable
key remains readable inside the sandbox; it is not a proxy placeholder.

The config seed disables background updates only when the settings file is
absent; existing settings are preserved. The enterprise auth/API/model hosts and the
Devin update/feature-flag hosts are allowed. GitHub, npm and crash-reporting
hosts require additional network grants.
