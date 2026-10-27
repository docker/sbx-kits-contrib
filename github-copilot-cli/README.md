# github-copilot-cli

A mixin kit that installs [GitHub CLI](https://cli.github.com/) and prepares
the sandbox to use GitHub Copilot CLI through `gh copilot`.

The kit intentionally does not try to pre-authenticate Copilot. GitHub Copilot
CLI is normally tied to the GitHub CLI authentication flow, so authenticate
inside the sandbox with `gh auth login` when your first Copilot command needs
it.

## Usage

Pair it with whichever sandbox agent you want to work from:

```console
$ sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-copilot-cli" ~/my-project
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=github-copilot-cli" ~/my-project
```

Or with a local checkout:

```console
$ sbx run shell --kit ./github-copilot-cli ~/my-project
```

Once attached, verify GitHub CLI is available:

```console
agent@sandbox:~$ gh --version
```

If Copilot CLI needs authentication, run:

```console
agent@sandbox:~$ gh auth login
agent@sandbox:~$ gh auth status
```

Then use Copilot CLI:

```console
agent@sandbox:~$ gh copilot -- --help
agent@sandbox:~$ gh copilot -p "Explain this repository"
```

`gh copilot` downloads the Copilot CLI on first use if a Copilot CLI binary is
not already available on `PATH`.

## What gets installed

The install hook adds GitHub CLI's official apt repository, installs the `gh`
package, and disables GitHub CLI update notices through `GH_NO_UPDATE_NOTIFIER`.

The kit does not install a separate npm package or community extension for
Copilot. The supported entrypoint is the GitHub CLI preview command:

```console
gh copilot
```

## Authentication

Use GitHub CLI's normal interactive authentication flow from inside the
sandbox:

```console
gh auth login
```

Copilot access is controlled by your GitHub account and Copilot entitlement.
If your organization requires a browser/device-code flow, complete that flow
when `gh auth login` prompts you.

This kit does not declare `GH_TOKEN` as a proxy-managed secret because Copilot
CLI authentication may involve OAuth/device credentials and local GitHub CLI
state rather than a single outbound API key header. Keeping authentication
explicit avoids placing unsupported or misleading credential wiring in the kit.

## Network policy

The kit's allowlist covers:

- GitHub CLI's official apt repository.
- GitHub release/download hosts used by GitHub CLI and first-run Copilot CLI
  downloads.
- GitHub and GitHub API hosts used by `gh auth`.
- GitHub Copilot service hosts used by Copilot CLI prompt traffic.
- Ubuntu and Docker apt hosts required by the base sandbox template during
  `apt-get update`.

If `gh copilot` reports a network error, run:

```console
$ sbx policy log <sandbox-name>
```

Add only the specific blocked host that is required for the command you are
running. Avoid broad wildcard allow rules unless you have verified they are
needed.

## Testing

Run the standard kit checks from the repo root:

```console
$ sbx kit validate ./github-copilot-cli
$ ./scripts/test-kit.sh github-copilot-cli
```

Then run a live sandbox:

```console
$ sbx run shell --kit ./github-copilot-cli .
```

Inside the sandbox:

```console
agent@sandbox:~$ gh --version
agent@sandbox:~$ gh auth login
agent@sandbox:~$ gh copilot -- --help
```

The live sandbox check is intentionally limited to install/auth readiness. A
prompt request requires an authenticated GitHub account with Copilot access.
