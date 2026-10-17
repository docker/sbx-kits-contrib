> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# al

A mixin that installs
[`altool`](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-al-tool),
the AL command-line compiler for
[Microsoft Dynamics 365 Business Central](https://learn.microsoft.com/en-us/dynamics365/business-central/),
together with the .NET 8 and .NET 10 runtimes it runs on, so the agent can build,
compile, and package AL extensions inside the sandbox.

## Usage

`al` is a mixin, so it cannot run on its own: it composes with `--kit`
onto a base agent. It is agent-agnostic — pick whichever you use:

```console
sbx run shell --kit docker.io/sbx/al:latest ~/my-al-project
```

Or from a git URL targeting this repo:

```console
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=al" ~/my-al-project
```

Or from a local clone — a local reference has to be an explicit path
(`./al`, not `al`):

```console
sbx run shell --kit ./al ~/my-al-project
```

Kit v3 needs an `sbx` release candidate or nightly build from
[docker/sbx-releases](https://github.com/docker/sbx-releases/releases);
the stable line does not load v3 kits.

Once attached, `al` is on `PATH`:

```console
agent@sandbox:~$ al --version
18.1.43.24897+799e32e9b48e151929e79fa662a5ddd4a2d4ebce
agent@sandbox:~$ al compile /project:~/my-al-project /packagecachepath:~/my-al-project/.alpackages
```

## How the install works

**altool and its runtime ship in the kit's image layers; nothing is
downloaded into your sandbox.** `al.dockerfile` runs at build time:

1. Installs the .NET 10 SDK into a throwaway build directory, and the
   ASP.NET Core 8 and 10 runtimes (each including the base .NET runtime)
   side by side into `/opt/al/dotnet`. altool is framework-dependent on
   exactly those two frameworks, in whichever major its release targets.
2. Installs the pinned `Microsoft.Dynamics.BusinessCentral.Development.Tools`
   package into `/opt/al/tools` with `dotnet tool install --tool-path`.
3. Writes `/usr/local/bin/al`, a small launcher that sets `DOTNET_ROOT`
   to `/opt/al/dotnet` for itself and execs the tool. Because the launcher
   carries its own `DOTNET_ROOT`, `al` works from any process — an
   interactive shell, a non-login hook, or an MCP server spawned directly
   by the agent — without exporting anything into your environment.
4. Checks the installed package version against the pin and that both
   runtime majors are present, deletes the SDK,
   and runs `al --version` against the shipped runtime alone, so an
   overlay that couldn't start fails the build rather than your sandbox.

Only the runtime, the tool and the launcher end up in the overlay. The
SDK is not shipped: the `dotnet` CLI is not on `PATH` in the sandbox.

Building at publish time rather than installing at sandbox creation
means no per-create download, a failure at the kit's build instead of in
your sandbox, a version you can see in the kit's tag, and no install-time
network access at all.

### Versions

The kit's `version` argument is the altool NuGet package version. It
defaults to the latest stable release at the time the kit was last
bumped, and it is the single source for the install, the `al@<version>`
the kit provides, and the tag it publishes under.

To build with a different release — including Microsoft's `-beta`
prereleases — override the argument:

```console
docker buildx build ./al -f al/al.yaml --build-arg version=30.0.43.45776-beta ...
```

The .NET 8 and 10 runtimes float to their latest servicing patch at each build,
so rebuilds pick up runtime security fixes without a kit change.

To bump the default, read
[the package's version index](https://api.nuget.org/v3-flatcontainer/microsoft.dynamics.businesscentral.development.tools/index.json),
take the newest entry without a `-beta` suffix, and update the `version`
argument's default in `al.yaml`.

## Using the AL MCP Server

Beyond the command-line compiler, `al` can run as a
[Model Context Protocol](https://modelcontextprotocol.io) server, exposing
AL-aware capabilities (compile, symbol lookup, project inspection) as tools
the agent can call directly. Launch it with:

```console
agent@sandbox:~$ al launchmcpserver --transport stdio .
```

The trailing `.` is the AL project directory the server operates on.

To let an agent use it, register the server in an `.mcp.json` at the root
of your AL workspace:

```json
{
  "mcpServers": {
    "al": {
      "command": "/usr/local/bin/al",
      "args": ["launchmcpserver", "--transport", "stdio", "."]
    }
  }
}
```

Notes:

- **`command`** is the absolute path to the launcher
  (`/usr/local/bin/al`) rather than a bare `al`, so the server resolves
  regardless of the agent's `PATH` at launch time.
- **No `env` block is needed.** The launcher sets `DOTNET_ROOT` itself.
- Agents that read a project-local `.mcp.json` (Claude Code among them)
  pick the server up automatically when started with the project mounted
  as the working directory.

## Network policy

The kit declares a `runtime` phase and **no `install` phase**, because
nothing it does at sandbox creation touches the network:

| Host | Why |
| --- | --- |
| `api.nuget.org` | nuget.org's v3 feed, for restoring AL symbol packages at run time |
| `globalcdn.nuget.org` | The CDN nuget.org serves package downloads from |

The hosts .NET and altool are installed from — `dot.net`,
`builds.dotnet.microsoft.com` and nuget.org — are reached by the kit's
build, not by the sandbox.

If you need to restore AL project dependencies from other feeds at
runtime — e.g. a corporate NuGet server or Business Central's symbols
API — add those hosts in a fork, under the `runtime` phase, or via a
per-sandbox allow rule:

```console
sbx policy allow network --sandbox <name> "your-nuget-feed.example.com"
```

## What the base must provide

The .NET runtime needs ICU, OpenSSL and zlib from the image it lands on.
Every `docker/sandbox-templates` base ships them, so the kit does not
declare them: requiring them by package name would tie the kit to one
Ubuntu release's sonames (`libicu78` today). On a custom base without
ICU, `al` fails at startup with a "Couldn't find a valid ICU package"
error.

## Scope of this kit

This is a thin install layer. It provides the `altool` compiler and the
.NET runtime it depends on — it does **not** ship symbol packages, a
Business Central server connection, or project scaffolding. Those belong
in your AL project repo, not in a generic kit.
