> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# code-server

A mixin that installs [code-server](https://github.com/coder/code-server)
and runs it as a background service on port 8080, with the
[Claude Code VS Code extension](https://code.claude.com/docs/en/vscode)
pre-installed. The kit requests port 8080 through a
`com.docker.sandbox/port@1` capability, so the sandbox runtime publishes
it on an ephemeral host port at start time — no separate
`sbx ports --publish` step is needed. You get a
web-based VS Code pointed at the sandbox workspace with a native Claude
panel that shares credentials and conversation history with the `claude`
CLI agent.

## Usage

Pair it with the built-in `claude` agent, from its published OCI artifact on Docker Hub:

```console
sbx run claude --kit "docker.io/docker/sbx-kit-code-server:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=code-server" ~/my-project
```

Once the sandbox is up, find the assigned host port:

```console
sbx ports <sandbox-name>
```

Open `http://localhost:<host-port>/` in a browser. code-server opens
the sandbox workspace on launch — no **File → Open Folder…** needed.
Click the **Spark** icon in the editor toolbar (top-right) to open the
Claude Code panel; it picks up the same auth the CLI uses.

If you'd rather pin the host port to a fixed value, the classic
`sbx ports <sandbox-name> --publish 8080:8080/tcp` still works
alongside the declared ephemeral binding.

If the page doesn't load, check the startup log inside the sandbox:

```console
sbx exec -it <sandbox-name> -- cat /tmp/code-server.log
```

## What's in the layer, and what happens at create

The editor and the extension are **built into the kit image**.
`code-server.dockerfile` runs the upstream `code-server.dev/install.sh`
and `code-server --install-extension anthropic.claude-code` at build
time and stages the result — `/usr/lib/code-server`,
`/usr/bin/code-server` and the unpacked extension under
`~/.local/share/code-server/extensions` — into an overlay. Creating a
sandbox therefore downloads neither the ~100 MB deb nor the ~235 MB
extension, and the version you get is fixed and scannable in the
published kit rather than resolved afresh in every sandbox.

The editor release is pinned, not merely frozen at whatever the last
publish resolved. The descriptor's `version` arg carries it, the recipe
passes it to the upstream script as `--version`, and the kit publishes
`provides: ["code-server@<version>"]` plus a top-level `version:` from
the same arg — so the publish tag names the editor release the overlay
carries, and a kit asking for `code-server >= 4.138` can resolve against
it. The build then runs `code-server --version` and fails unless the
installed editor reports the pinned number. To bump it, set the arg's
default to what the install script itself would resolve:

```console
curl -fsSLI -o /dev/null -w '%{url_effective}\n' \
  https://github.com/coder/code-server/releases/latest
```

The preinstalled `anthropic.claude-code` extension is not part of that
claim — it is resolved from open-vsx at build time, and the provide is
about the editor.

One consequence worth knowing: the kit's network policy has **no
`install` phase**. Nothing it does at create time reaches a host. The
only grant left is the open-vsx marketplace at runtime, so installing
further extensions from the Extensions view still works.

Two things stay lifecycle hooks, because neither of them is content: the
wrapper script below, which needs a workspace path that does not exist
until the sandbox is created, and the background start.

## How the workspace path gets set

A lifecycle install hook writes a tiny wrapper script at
`/home/agent/.local/bin/start-code-server.sh`, reading `WORKSPACE_DIR`
from its declared `env:` and single-quoting the value into the script, so
the wrapper has the correct folder baked in before `code-server` runs. A
lifecycle startup hook invokes the script with `background: true` —
the engine detaches it — and redirects stdout/stderr to
`/tmp/code-server.log`.

The workspace path isn't known until the sandbox is created, so it can't
be hardcoded in a static file. It has to be read from the environment,
and a hook is the only lifecycle declaration that gets an environment: a
`files:` entry's `content` expands `${{ kit.args.* }}` and nothing else,
so a `$WORKSPACE_DIR` written there would reach the script as literal
text rather than as the workspace path.

## About authentication

The startup command passes `--auth none`. code-server is only reachable
through the runtime's published-port binding, which lands on `localhost`
on your host by default, so you're already behind the sandbox boundary.
If you want a password anyway, override the startup command in a forked
kit.

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
After that, state persists across browser reloads. This kit requests no
volume of its own, so whether `~/.local/share/code-server/` survives a
sandbox recreate is up to the base workload's own storage.

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
