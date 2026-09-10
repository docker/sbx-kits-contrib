# al

A mixin kit (`kind: mixin`) that installs
[`altool`](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-al-tool),
the AL command-line compiler for
[Microsoft Dynamics 365 Business Central](https://learn.microsoft.com/en-us/dynamics365/business-central/),
so the agent can build, compile, and package AL extensions inside the
sandbox.

## Usage

`al` is agent-agnostic — pair it with whichever agent you're using:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=al" claude ~/my-al-project
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=al" shell ~/my-al-project
```

Or with a local clone of this repo:

```console
$ sbx run --kit ./al/ claude ~/my-al-project
```

After install, the `al` command is available on `PATH`:

```console
agent@sandbox:~$ al --help
agent@sandbox:~$ al compile /project:~/my-al-project /packagecachepath:~/.alpackages
```

## How the install works

The install step runs as the agent user (`user: "1000"`) and does two
things:

1. **Installs the .NET 8.0 runtime/SDK** via the upstream
   `dotnet-install.sh` script, into `/home/agent/.dotnet`. `altool`
   ships as a .NET global tool and needs the runtime to execute.
2. **Installs `altool`** — the
   `Microsoft.Dynamics.BusinessCentral.Development.Tools` global tool
   — from NuGet into `~/.dotnet/tools`, which is on the agent's `PATH`.

## Using the AL MCP Server

Beyond the command-line compiler, the `al` tool can run as a
[Model Context Protocol](https://modelcontextprotocol.io) server, exposing
AL-aware capabilities (compile, symbol lookup, project inspection) as tools
the agent can call directly. Launch it with:

```console
agent@sandbox:~$ al launchmcpserver --transport stdio .
```

The trailing `.` is the AL project directory the server operates on.

To let an agent use it, register the server in an `.mcp.json` at the root
of your AL workspace. It should look like this:

```json
{
  "mcpServers": {
    "al": {
      "command": "/home/agent/.dotnet/tools/al",
      "args": ["launchmcpserver", "--transport", "stdio", "."],
      "env": {
        "DOTNET_ROOT": "/home/agent/.dotnet"
      }
    }
  }
}
```

Notes:

- **`command`** is the absolute path to the `al` global tool
  (`/home/agent/.dotnet/tools/al`) rather than a bare `al`, so the server
  resolves regardless of the agent's `PATH` at launch time.
- **`DOTNET_ROOT`** must point at the .NET install (`/home/agent/.dotnet`)
  so the tool can locate its runtime — the same directory the kit's
  install step created.
- Agents that read a project-local `.mcp.json` (Claude Code among them)
  pick the server up automatically when started with the project mounted
  as the working directory. Drop the file into the AL project you mount,
  or use the repo's example as a template.

## Network policy

`allowedDomains` covers exactly the hosts the install needs:

| Host | Why |
| --- | --- |
| `dot.net` | Entry point for the `dotnet-install.sh` bootstrap script |
| `ci.dot.net` | Redirect target the install script resolves to |
| `builds.dotnet.microsoft.com` | Where the .NET runtime/SDK archives are hosted |
| `api.nuget.org` | NuGet feed the `altool` global tool package is pulled from |

If you need to restore AL project dependencies (symbol packages) at
runtime from other feeds — e.g. a corporate NuGet server or Business
Central's symbols API — add those hosts in a fork or via a per-sandbox
allow rule:

```console
$ sbx policy allow network --sandbox <name> "your-nuget-feed.example.com"
```

## Scope of this kit

This is a thin install layer. It provides the `altool` compiler and the
.NET runtime it depends on — it does **not** ship symbol packages, a
Business Central server connection, or project scaffolding. Those belong
in your AL project repo, not in a generic kit.
