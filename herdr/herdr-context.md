# herdr

This sandbox opens in herdr, a terminal multiplexer for coding agents. herdr
keeps workspaces, tabs and split panes in a server inside the sandbox, so
whatever runs in a pane keeps running after the user detaches. When
`HERDR_ENV=1` is set, you are in one of those panes.

- The `herdr` CLI drives that server from any pane: create workspaces, tabs
  and panes, run commands in a pane, read its output, and list the agents
  running in panes (`herdr agent list`). `herdr --skill` prints the full guide
  to driving it, and `herdr --help` lists every command.
- Panes are bash login shells that start in the workspace, with git, curl,
  jq, Python 3, Node and a Docker engine. The apt cache starts empty: run
  `sudo apt-get update` before `sudo apt-get install -y <package>`.
- Outbound network access is limited by the sandbox's network policy. If a
  request is blocked, say so rather than working around it.
