# kiro-host-auth (prototype)

A declaration-only mixin for the [`kiro`](https://hub.docker.com/r/sbx/kiro) workload that keeps Kiro CLI's AWS sign-in tokens on the host instead of in the sandbox.

Without it, `kiro-cli login` stores the real access and refresh tokens in `~/.local/share/kiro-cli/data.sqlite3` inside the sandbox. With it, you still sign in from the sandbox, but the sandbox proxy intercepts the AWS SSO OIDC token endpoint, stores the real tokens in the host credential store under the `kiro` service, and returns placeholder tokens to kiro-cli. The proxy then substitutes the real access token on Kiro's chat API and the real refresh token when kiro-cli refreshes.

> [!WARNING]
> Prototype. It needs an sbx build whose proxy accepts AWS SSO OIDC token requests (device_code sign-in and camelCase JSON bodies); released sbx versions reject both. It has not yet been tested against a real Kiro sign-in.

## Try it

1. Build sbx from the proxy change and use an isolated daemon, so your normal sbx state is untouched:

   ```console
   gh pr checkout 10114 --repo docker/sandboxes
   task build:test-binaries
   task check:runtime
   alias sbx-kiro="$PWD/bin/sbx --app-name kiro-host-auth-test"
   sbx-kiro login
   ```

   On macOS, run sbx from an isolated install instead of `bin/sbx`, as the docker/sandboxes `cli-tester` skill's Environment Setup describes (`task install:ci SBX_PREFIX=… CHECK_PATH=false`), and point the alias at that prefix.

2. Create a `kiro` sandbox with this mixin from the PR branch. Set `region` to your IAM Identity Center region; Builder ID users can omit it (default `us-east-1`). Approve the `kiro` OAuth binding when sbx asks:

   ```console
   sbx-kiro create --name kiro-host-auth docker.io/sbx/kiro:latest \
     --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=kiro-host-auth&dir=kiro-host-auth" \
     --kit-arg region=eu-central-1
   ```

3. Sign in. The workload's entrypoint is `kiro-cli chat`, so run the login through `exec` and finish the device flow in your browser:

   ```console
   sbx-kiro exec -it kiro-host-auth kiro-cli login --use-device-flow
   ```

   For Identity Center, pass your start URL and region as kiro-cli prompts for them.

4. Check that kiro-cli's state holds the placeholders, then chat:

   ```console
   sbx-kiro exec kiro-host-auth sh -c 'grep -a -o "sbx-kiro-[a-z-]*" ~/.local/share/kiro-cli/data.sqlite3* | sort -u'
   sbx-kiro run --name kiro-host-auth
   ```

   The first command should print `sbx-kiro-access-managed-by-proxy` and `sbx-kiro-refresh-managed-by-proxy`. It shows the placeholders are present, not that no real token is; sign in on a fresh sandbox so no earlier token is left in the state. Leave the chat open past the access token's lifetime (usually an hour) to exercise a refresh through the proxy. If something fails, `sbx-kiro policy log kiro-host-auth` shows blocked hosts and `sbx-kiro daemon logs` shows the proxy's `kiro` lines.

5. Clean up. `reset -f` removes the isolated daemon's sandboxes and state, including the captured Kiro tokens, which `rm` alone leaves in the host credential store:

   ```console
   sbx-kiro reset -f
   ```

## Known limitations

- **One sign-in per sandbox.** kiro-cli keeps its OIDC client registration in its SQLite state, and a refresh token works only with the client that obtained it. A new sandbox has no registration, so it signs in again, and that sign-in replaces the host-held tokens. Another sandbox that is still running then fails its next refresh and has to sign in again. Reusing one sign-in across sandboxes needs the proxy to keep the client registration as well.
- **One region per sandbox.** The token endpoint is `oidc.<region>.amazonaws.com`, fixed when the sandbox is created.
- **`sbx secret` does not list or remove the `kiro` token yet.** `kiro-cli logout` clears only the placeholders in the sandbox; the host keeps the tokens until the next sign-in replaces them or `sbx reset` removes every stored secret.
- **Social sign-in (Google, GitHub) is not covered.** It uses Kiro's own auth service, not AWS SSO OIDC.
- The proxy routes every request to the OIDC host to the `kiro` service, so once a token is stored, client registration and device authorization requests also carry it as a bearer. Whether AWS ignores that header is unverified.
- The chat hosts that receive the bearer (`resourceHosts`) are taken from kiro-cli's open-source predecessor and the `kiro` workload's allow list; a live run may surface more.
