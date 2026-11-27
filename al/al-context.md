## AL (Business Central)

`al` (altool, the AL command-line compiler for Microsoft Dynamics 365
Business Central) is installed and on `PATH`. Run `al --help` for its
commands, and compile an AL project with:

```sh
al compile /project:<project-dir> /packagecachepath:<project-dir>/.alpackages
```

The project's symbol packages (`.app` files in `.alpackages`) must be
present or restorable; outbound access is limited to nuget.org unless
the sandbox's network policy allows more.

`al launchmcpserver --transport stdio <project-dir>` starts an MCP server
exposing AL-aware tools (compile, symbol lookup, project inspection) for
that project.
