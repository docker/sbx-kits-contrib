# kiro-host-auth (prototype)

A mixin for the [`kiro`](https://hub.docker.com/r/sbx/kiro) workload that keeps Kiro CLI's AWS sign-in on the host instead of in the sandbox.

Without it, `kiro-cli login` stores the real access and refresh tokens in `~/.local/share/kiro-cli/data.sqlite3` inside the sandbox. With it, you sign in on the host with `sbx secret set kiro --oauth`. sbx keeps the tokens and the AWS client they belong to in the host credential store and refreshes them itself, and the sandbox proxy adds the access token to Kiro's API requests. kiro-cli's state in the sandbox holds only placeholders, and the sandbox cannot reach AWS's sign-in endpoint at all.

> [!WARNING]
> Prototype. It needs an sbx build with the host-side Kiro sign-in, which no sbx release has yet. It has not yet been tested against a real Kiro sign-in.

## Try it

1. Build sbx from the sbx change and use an isolated daemon, so your normal sbx state is untouched:

   ```console
   gh pr checkout 10114 --repo docker/sandboxes
   task build:test-binaries
   task check:runtime
   alias sbx-kiro="$PWD/bin/sbx --app-name kiro-host-auth-test"
   sbx-kiro login
   ```

   On macOS, run sbx from an isolated install instead of `bin/sbx`, as the docker/sandboxes `cli-tester` skill's Environment Setup describes (`task install:ci SBX_PREFIX=… CHECK_PATH=false`), and point the alias at that prefix.

2. Sign in to Kiro on the host. sbx asks for your IAM Identity Center start URL and region (leave the start URL empty for AWS Builder ID), opens the AWS sign-in page, and shows a code to confirm there:

   ```console
   sbx-kiro secret set kiro --oauth
   ```

3. Create a `kiro` sandbox with this mixin from the PR branch. Pass the same start URL and region you signed in with; Builder ID users can omit both. Approve the `kiro` OAuth binding when sbx asks:

   ```console
   sbx-kiro create --name kiro-host-auth docker.io/sbx/kiro:latest \
     --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=kiro-host-auth&dir=kiro-host-auth" \
     --kit-arg startUrl=https://d-1234567890.awsapps.com/start \
     --kit-arg region=eu-central-1
   ```

4. Check that kiro-cli sees a sign-in, then chat:

   ```console
   sbx-kiro exec kiro-host-auth kiro-cli whoami
   sbx-kiro run --name kiro-host-auth
   ```

   `whoami` should print `Logged in with Builder ID` or `Logged in with IAM Identity Center (…)`. With Identity Center, kiro-cli may ask you to pick a Kiro profile; run `sbx-kiro exec -it kiro-host-auth kiro-cli profile` if it does. Leave the chat open past the access token's lifetime (usually an hour) to exercise a refresh on the host. If something fails, `sbx-kiro policy log kiro-host-auth` shows blocked hosts and `sbx-kiro daemon logs` shows the proxy's `kiro` lines.

5. Clean up. `secret rm` deletes the host sign-in; `reset -f` removes the isolated daemon's sandboxes and state:

   ```console
   sbx-kiro secret rm kiro
   sbx-kiro reset -f
   ```

## Known limitations

- **Sign in on the host first.** The sandbox always carries the placeholder sign-in, so without a host sign-in kiro-cli believes it is signed in and Kiro's API rejects its requests. Run `sbx secret set kiro --oauth`; the next request uses the new sign-in.
- **The start URL and region are given twice**, to `sbx secret set kiro --oauth` and as kit arguments, and they must match. The kit arguments only label the placeholder sign-in; the host's sign-in decides which account the requests use.
- **Identity Center profile selection is unverified.** kiro-cli stores the chosen profile in the sandbox; it is not a secret, but each new sandbox may ask again.
- **Organizations can disable device-code sign-in** for Identity Center. sbx then cannot sign in on the host.
- **The AWS client registration expires**, after about 90 days. Refreshing then fails, and you sign in again with `sbx secret set kiro --oauth`.
- **`kiro-cli logout` in the sandbox removes the placeholders**, and kiro-cli then reports no sign-in. Recreate the sandbox to restore them; the host sign-in is unaffected.
- **Social sign-in (Google, GitHub) is not covered.** It uses Kiro's own auth service, not AWS SSO OIDC.
- The chat hosts that receive the bearer (`resourceHosts`) are taken from kiro-cli's open-source predecessor and the `kiro` workload's allow list; a live run may surface more.
