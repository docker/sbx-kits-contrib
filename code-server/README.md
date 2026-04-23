# code-server

A mixin that installs [code-server](https://github.com/coder/code-server)
and runs it as a background service on port 8080, with the
[Claude Code VS Code extension](https://code.claude.com/docs/en/vscode)
pre-installed. Combined with `sbx ports --publish`, you get a web-based
VS Code pointed at the sandbox workspace with a native Claude panel that
shares credentials and conversation history with the `claude` CLI agent.

## Usage

Pair it with the built-in `claude` agent:

```console
$ sbx run claude --kit "git+https://github.com/dvdksn/kits-cookbook.git#dir=code-server" ~/my-project
```

Publish the port from your host:

```console
$ sbx ports <sandbox-name> --publish 8080:8080/tcp
```

Open `http://localhost:8080/` in a browser. code-server opens the
sandbox workspace on launch — no **File → Open Folder…** needed.
Click the **Spark** icon in the editor toolbar (top-right) to open the
Claude Code panel; it picks up the same auth the CLI uses.

If the page doesn't load, check the startup log inside the sandbox:

```console
$ sbx exec -it <sandbox-name> -- cat /tmp/code-server.log
```

## How the workspace path gets set

The kit uses `commands.initFiles` to write a tiny wrapper script at
`/home/agent/.local/bin/start-code-server.sh` each time the sandbox
starts. `${WORKDIR}` expands to the actual workspace path at that
point, so the script has the correct folder baked in before
`code-server` runs. `commands.startup` invokes it via `sh <script>`
(the `mode` field on initFiles didn't reliably apply the execute
bit, so we sidestep needing it), backgrounded with `nohup … &`,
stdout/stderr redirected to `/tmp/code-server.log`.

This is the cleanest place to see why `initFiles` exists — the
workspace path isn't known until the sandbox starts, so it can't be
hardcoded in a static file or a shell-string command.

## About authentication

The startup command passes `--auth none`. code-server is only reachable
through `sbx ports`, which publishes to `localhost` on your host by
default, so you're already behind the sandbox boundary. If you want a
password anyway, override the startup command in a forked kit.

### Claude Code extension auth

The extension and the `claude` CLI share state in `~/.claude/` and both
read `ANTHROPIC_API_KEY` from the environment. The built-in `claude`
agent already routes Anthropic auth through the sandbox credential
proxy, so the extension inherits that: no separate sign-in required.

If the extension shows a sign-in prompt when you open the Spark panel,
check that the underlying CLI is authenticated first (run `claude` in
the integrated terminal inside VS Code, or `sbx attach` to the agent).

## Shipped VS Code settings

The kit drops a minimal `User/settings.json` into code-server's user
data directory to reduce first-launch noise:

```json
{
  "workbench.startupEditor": "none",
  "chat.commandCenter.enabled": false,
  "workbench.tips.enabled": false,
  "telemetry.telemetryLevel": "off",
  "claudeCode.preferredLocation": "sidebar"
}
```

- `startupEditor: "none"` — no welcome page on launch
- `chat.commandCenter.enabled: false` — hides the built-in chat widget
  that newer VS Code ships in the top bar
- `claudeCode.preferredLocation: "sidebar"` — Claude opens in the
  right-hand sidebar rather than a full editor tab

VS Code doesn't have a clean "auto-open this view on startup" setting,
so Claude still needs one click on the Spark icon the first time.
After that, state persists across browser reloads (the sandbox's
`persistence: persistent` volume preserves `~/.local/share/code-server/`).

Edit `files/home/.local/share/code-server/User/settings.json` in a fork
to customize further.

## Can I run a native editor (Cursor, Zed, …) like this?

Not through this kit, but it's plausible as a follow-up recipe.
code-server works because VS Code has a first-party web server mode —
Cursor, Zed, and most other editors don't. To run one of those in a
sandbox and use it from the host browser, the cleanest path is
probably [xpra](https://xpra.org/) with its HTML5 client: xpra starts
the editor under a virtual display and serves its window to a browser
over HTTPS, without the latency and clipboard limitations of VNC.
A kit would install xpra + the editor, then run
`xpra start --start-child=<editor> --bind-tcp=0.0.0.0:14500 --html=on`
as a startup command.
