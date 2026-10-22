> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# herdr

A sandbox that opens in [herdr](https://herdr.dev), a terminal multiplexer for
coding agents: workspaces, tabs and split panes, held by a server inside the
sandbox that you attach to and detach from. herdr recognizes the agents
running in its panes and shows each one's state in its sidebar.

Underneath is what the [`shell`](../shell) kit runs: the hardened Debian 13
template with Docker's certificate-trust fixes, carrying bash, git, apt, a
Docker engine with compose and buildx, curl, gh, jq, make, gcc, Python 3 and
Node with npm. On top is one static binary, herdr at a pinned release, which
is what `sbx run` launches.

No agent is installed. Agents come as mixins, which compose onto this kit the
way they compose onto `shell`, and each one runs in a pane.

## Usage

```console
sbx run docker.io/sbx/herdr:latest
```

Or from a git URL targeting this repo:

```console
sbx run "git+https://github.com/docker/sbx-kits-contrib.git#dir=herdr"
```

Or from a local clone:

```console
sbx run ./herdr
```

herdr opens in your workspace without its first-run setup screen. Give the
sandbox a name with `--name` to make coming back to it easy; `sbx ls` shows
the name otherwise.

### With agents

Compose agent mixins with `--kit`, one per agent:

```console
sbx run --kit docker.io/sbx/claude-mixin:latest \
        --kit docker.io/sbx/codex-mixin:latest \
        docker.io/sbx/herdr:latest
```

Then start each agent in a pane: `claude` in one, `codex` in another.
`ctrl+b v` splits the focused pane. Each mixin brings its own credential and
the hosts its agent needs, so bind the services you use on the host
(`sbx secret set anthropic`, `sbx secret set openai`) as you would for that
agent alone. The first time you create a sandbox with them, sbx lists the
credentials the mixins declare and asks you to approve them, and it
remembers the answer.

## Provider credentials

This kit declares none, which is what lets it host agent mixins: v3 gives each
credential one owner across a composed set, so a base that claimed
`anthropic` could not host `claude-mixin`, and one that claimed `openai`
could not host `codex-mixin`.

For provider keys in a sandbox with no agent mixin, compose
[`shell-credentials`](../shell-credentials) beside it:

```console
sbx run --kit docker.io/sbx/shell-credentials:latest docker.io/sbx/herdr:latest
```

That adds eight provider services, each injected by the sandbox proxy on
requests to that provider's hosts. It does not compose with an agent mixin
that owns one of the same services, such as `claude-mixin` (`anthropic`),
`codex-mixin` (`openai`) or `copilot-mixin` (`github`): sbx refuses to create
the sandbox and names both kits.

## Sessions

The session lives in herdr's server inside the sandbox, not in your terminal:

| To | Run |
| --- | --- |
| Detach | `ctrl+b q` |
| Attach again | `sbx run --name <sandbox>` |
| Attach a second client from another terminal | `sbx exec -it <sandbox> herdr` |
| Drive it from a script | `sbx exec <sandbox> -- herdr agent list` |

The scripting commands are herdr's own CLI (`herdr pane list`,
`herdr pane run`, `herdr workspace create`, …), run inside the sandbox. Run
them through `sbx exec`: in a pane of a herdr on your host, a bare `herdr`
talks to that host session instead.

The kit asks the runtime to keep the sandbox running after its last session
ends (`long-running@1`), and sbx does: detached panes, and the agents working
in them, carry on until you stop the sandbox. `sbx ls --json` reports such a
sandbox as `"detached": true`.

```console
sbx stop <sandbox>
```

The capability is optional. An `sbx` that cannot honor it skips it and keeps
its ordinary auto-stop: the sandbox stops about 30 seconds after the last
`sbx run` or `sbx exec` session ends, detaching from herdr included. To keep
the panes alive there, leave a session open, for example in a spare terminal:

```console
sbx exec <sandbox> -- sleep infinity
```

When the sandbox stops, either way, herdr's server and every process in its
panes end with it. The next `sbx run --name <sandbox>` starts it again, and
herdr restores its last saved layout: the same workspaces, tabs, panes and
directories, with fresh shells in the panes (see herdr's
[session state and restore](https://herdr.dev/docs/session-state/)).

## Inside another herdr or tmux

Started from a pane of another herdr, or inside tmux, the outer one sees
`ctrl+b` first. Two ways through:

- **Press it twice.** herdr and tmux both pass a literal `ctrl+b` to the pane
  when their prefix is pressed twice, so `ctrl+b ctrl+b` followed by a key
  drives the herdr in the sandbox: `ctrl+b ctrl+b q` detaches from it.
- **Give the sandbox's herdr its own prefix.** Add this to
  `~/.config/herdr/config.toml` in the sandbox, then run
  `herdr server reload-config` there, which applies it to attached clients
  too:

  ```toml
  [keys]
  prefix = "ctrl+a"
  ```

Leave the outer session's `HERDR_*` variables out of `sbx run -e`. herdr
refuses to start where `HERDR_ENV=1` says it is already inside a herdr pane.

## Panes

Every pane runs `/bin/bash` as a login shell, the shell the `shell` kit
launches, so it reads the same files. That includes the `/etc/profile.d`
drop-ins agent mixins ship for their agents' environment, so `claude`, `codex`
and the rest start in a pane as they would in the `shell` kit's shell.

A pane's environment comes from herdr's server, which starts on your first
attach and keeps the environment it started with. Every pane opened later gets
the same one. `sbx run --name <sandbox> -e NAME=value` reaches the herdr client
you attach with, but no pane, old or new. To change what panes get, stop the
server, which ends every process in its panes, then attach with the new value:

```console
sbx exec <sandbox> -- herdr server stop
sbx run --name <sandbox> -e NAME=value
```

herdr restores the layout, and the fresh shells in it start with the new
environment. For one new pane there is a lighter way: `herdr pane split`,
`herdr tab create` and `herdr workspace create` take `--env KEY=VALUE` for the
shell they start.

For every pane opened from now on, without a restart, export the variable
from `/etc/sandbox-persistent.sh`, which login shells and bash scripts in the
sandbox source:

```console
sbx exec <sandbox> -- sh -c 'echo "export NAME=value" >> /etc/sandbox-persistent.sh'
```

Shells already running keep the environment they started with.

## Configuration

The image ships herdr's config at `~/.config/herdr/config.toml`, owned by the
agent user:

```toml
onboarding = false

[terminal]
default_shell = "/bin/bash"
shell_mode = "login"

[update]
version_check = false
manifest_check = false

[ui.sound]
enabled = false
```

- `onboarding = false` skips the first-run setup screen.
- `default_shell` and `shell_mode` make every pane a bash login shell. herdr's
  defaults would start `$SHELL`, or `/bin/sh` when it is unset, and on Linux
  never as a login shell.
- `version_check` and `manifest_check` stop herdr's background requests to
  herdr.dev. herdr is pinned in the image, so an update notice would have
  nothing to act on, and the agent-detection rules stay the ones built into
  that version.
- Sounds are off: a sandbox has no audio device.

The file in the sandbox also carries a comment on each key. It is yours to
change, and herdr writes to it as well: its settings screen saves there.
Edits survive `sbx stop` and a restart. Edit it in a pane and apply the edit
with `herdr server reload-config`; `herdr --default-config` prints every key
with its default.

herdr reads the file when its server starts. If it is missing then, or fails
to parse, herdr ignores it and runs on its defaults: the first-run screen,
`$SHELL` as a non-login shell, and both herdr.dev checks on. So run
`herdr config check` after an edit, before the server next starts; a reload of
a file that fails to parse keeps the config already loaded. A restart does not
restore a deleted or broken file; only a newly created sandbox starts from the
image's copy. To get the kit's settings back in place, copy the pristine one
the image keeps:

```console
cp /usr/local/share/herdr-kit/config.toml ~/.config/herdr/config.toml
```

## Agent guidance

Two things reach agents from this kit, and they reach different places:

- **herdr's skill.** `herdr --skill` prints a guide that teaches an agent to
  drive herdr from inside a pane: open panes, run commands, read their output.
  The image keeps the one that matches its binary, and the runtime exposes it
  as `herdr` in every skills directory a composed kit declares:
  `~/.claude/skills/herdr` for `claude-mixin`, `~/.agents/skills/herdr` for
  `codex-mixin`. An agent mixin that declares no skills directory, such as
  `copilot-mixin`, gets no copy. A skill already named `herdr` there, such as
  one in your host's shared skills store, is kept, and the bundled one is
  skipped. With no skills directory in the set there is nowhere for it to go,
  so it is skipped too.
- **The profile.** The kit names `AGENTS.md` as the profile file, and sbx
  writes it beside the workspace. sbx keeps the workspace at its host path
  inside the sandbox, so for a workspace at `/Users/you/src/app` the profile
  is `/Users/you/src/AGENTS.md`, in the sandbox only. It holds the runtime's
  own notes, which end by pointing at this kit's guidance
  (`/usr/share/sandbox/kit/herdr/herdr-context.md`), then a "Kits" index
  pointing at each mixin's. Neither Claude Code nor Codex reads it by itself.
  Claude Code reads `CLAUDE.md` files, and Codex stops looking for
  `AGENTS.md` at the root of the repository it runs in, so point an agent at
  the file when you want it to read it.

herdr detects the agents it supports without any setup. For more, herdr can
install hooks into an agent's own configuration, which let it resume that
agent's conversation in its pane after the server restarts and let some
agents report their state directly:

```console
herdr integration install claude
```

That writes into the agent's config files, which belong to its mixin, so the
kit leaves it to you.

## Worktrees

herdr can create a git worktree per branch (`ctrl+b shift+g`). It puts them
under `~/.herdr/worktrees`, which is inside the sandbox rather than in your
workspace, while git records each one in your repository's `.git/worktrees/`,
which is on your host, under that in-sandbox path. Two consequences:

- On the host, `git worktree list` marks these worktrees prunable, and
  `git worktree prune` deletes their records while the sandbox still uses
  them.
- `sbx rm` deletes the checkouts. Commits made in them are in your repository
  and survive; uncommitted changes do not.

Commit, or push, before you remove the sandbox. `sbx rm` leaves those records
behind; run `git worktree prune` on the host afterwards to drop them.

## Network

Two hosts: `deb.debian.org` and `dhi.io`, the image's apt sources, the same as
`shell`'s. The apt cache starts empty, so refresh it before the first install;
both sources are allowed, so this works under a deny-all policy:

```console
sudo apt-get update && sudo apt-get install -y <package>
```

herdr adds nothing. Its only automatic network use is checking herdr.dev for a
newer version and for updated agent-detection rules, and both checks are off
in the config above. Commands you run yourself reach the network too:
`herdr update`, `herdr server update-agent-manifests` and
`herdr plugin install`. herdr.dev is deliberately not allowed, so a check
switched back on fails closed under deny-all; under a permissive host policy,
the config is what keeps herdr from making those requests.

Agent mixins bring the hosts their agents need. Anything else, such as a
language package registry or the Docker registry hosts `docker pull` uses, is
yours to allow for that one sandbox:

```console
sbx policy allow network --sandbox <sandbox> registry.npmjs.org
```

## What it declares

- **`sbx@1`.** The host launches the image's command, herdr, and honors the
  image's user.
- **`long-running@1`, optional.** The sandbox keeps running with no session
  attached, so detached panes do too. See [Sessions](#sessions).
- **Network.** `deb.debian.org` and `dhi.io`, the apt sources, and nothing
  else.
- **`AGENTS.md`.** The profile file, which indexes every composed kit's
  guidance, with this kit's own short body. The workload names the profile;
  the agent mixins here contribute a body without naming one.
- **`agent-skill@1`, optional.** herdr's skill, exposed in the skills
  directories composed kits declare. See [Agent guidance](#agent-guidance).
- **`herdr@<version>`.** The provide another kit can `require`, at the pinned
  release.

No credentials and no lifecycle hooks. The image config states the rest:
`ENTRYPOINT ["herdr"]` with no `CMD`, `USER agent`,
`WORKDIR /home/agent/workspace`, `SHELL=/bin/bash`, `LANG=C.UTF-8`, and
`com.docker.sandboxes.flavor=herdr`. The base supplies
`com.docker.sandboxes.start-docker=true`, which starts the Docker engine.

## Content and building

[`herdr.dockerfile`](./herdr.dockerfile) starts with a marked section that
patches the template until it ships Docker's certificate-trust fixes itself.
It is the `shell` kit's certificate-trust step, copied word for word, so the
two images carry the same packages from DHI's signed apt
repository, which carries them ahead of the template.

The recipe then downloads the herdr release binary for the target
architecture, checks it against a SHA-256 digest pinned in the recipe, and
asserts that it reports the pinned version. The same build writes the skill
file from `herdr --skill` and bakes in the config.

```console
cd herdr
docker buildx build . -f herdr.yaml --output type=cacheonly   # validates
cd .. && sbx kit inspect ./herdr                              # what it resolved to
```

Building through `herdr.yaml` is what validates the descriptor: the kit
frontend checks it during the build and fails on a bad one. `sbx kit validate`
does not accept a v3 source kit.

### Upgrading herdr

The version drives the download, the `provides` entry and the published tag,
and the recipe fails the build when the binary does not match its digest. So
a bump moves four values together:

1. The `version` arg's default in [`herdr.yaml`](./herdr.yaml).
2. `HERDR_VERSION`, `HERDR_SHA256_AMD64` and `HERDR_SHA256_ARM64` in
   [`herdr.dockerfile`](./herdr.dockerfile). Take the digests GitHub records
   for the release assets, and check them against the `sha256` values
   https://herdr.dev/latest.json lists for the same release:

   ```console
   gh api repos/herdrdev/herdr/releases/tags/v<version> \
     --jq '.assets[] | select(.name|test("^herdr-linux-")) | "\(.name) \(.digest)"'
   ```

3. Build, which re-reads `herdr --version` and fails on a mismatch.

A bump is also how herdr's agent detection gets updated: its detection rules
ship inside the binary, and the config turns off their refresh from herdr.dev.

## Why there is no herdr-mixin

Most agents here come in two shapes, a workload and a `-mixin` that layers the
same agent onto another workload. herdr comes only as a workload. Its whole job
is to be the launch command, and a mixin's `ENTRYPOINT` is ignored when it is
composed, so a herdr mixin could add the binary but not make it the launch
command. herdr ships as the workload instead, and agents ship as the mixins
that compose onto it.

## Debugging

```console
sbx exec <sandbox> -- herdr status
sbx exec <sandbox> -- herdr config check
sbx exec <sandbox> -- tail -n 50 /home/agent/.config/herdr/herdr-server.log
sbx policy log <sandbox>
```

herdr keeps its logs beside its config, in `~/.config/herdr/`; the server's is
`herdr-server.log`, and `herdr --help` lists the rest. `sbx policy log` shows
what the proxy allowed and blocked for the sandbox. A blocked `herdr.dev`
there means herdr tried to reach it: a check switched back on, a config that
is missing or failed to parse, or a manual `herdr update`.

The kit describes itself inside the sandbox: `/usr/share/sandbox/kit/herdr/`
holds the published descriptor (`kit.yaml`), the recipe (`kit.dockerfile`) and
this kit's guidance body.
