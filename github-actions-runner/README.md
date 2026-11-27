# GitHub Actions Runner

A v3 mixin that adds an ephemeral GitHub Actions self-hosted runner for one job.
It pairs with a workload that can run the Actions runner and has the dependencies
required by the workflow, plus `setsid` (util-linux or busybox).

## Usage

A dispatcher outside the sandbox obtains a short-lived JIT configuration from
GitHub's `generate-jitconfig` API and sets it as `RUNNER_JITCONFIG` in the
environment of the `sbx` process. Pass the variable by name (`-e RUNNER_JITCONFIG`)
so the value is not written into the command line or shell history. The sandbox
receives no GitHub token.

Use the published image after it is available:

```console
sbx --cloud create --kit docker.io/sbx/github-actions-runner:latest -e RUNNER_JITCONFIG shell
```

Or load the kit from Git:

```console
sbx --cloud create --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=v3&dir=github-actions-runner" -e RUNNER_JITCONFIG shell
```

Or use a local checkout:

```console
sbx --cloud create --kit ./github-actions-runner -e RUNNER_JITCONFIG shell
```

## How it works

- **One JIT configuration, one start.** The startup hook hands the configuration
  to the runner through the runner's own input variable
  (`ACTIONS_RUNNER_INPUT_JITCONFIG`, which the runner masks and removes from its
  environment, so job steps do not inherit it) and marks the runner as started
  before launching it. A reboot never reuses a spent configuration. The value
  stays readable inside the sandbox to the runner's user until the job ends, as
  the runner's credential files do.
- **Credentials are removed.** When the runner exits, or the hook receives TERM
  or INT (it also sends TERM to the runner's whole process group, since `run.sh`
  passes no signal on to the listener), the hook removes `.runner`, `.credentials` and
  `.credentials_rsaparams`. After a KILL or a reboot, the next boot removes any
  the earlier run left, whether or not a configuration is supplied. The hook's log is
  `/tmp/actions-runner.log`; the runner's diagnostics are in
  `/opt/actions-runner/_diag`. `run.sh` reports exit status 0 for most failures,
  including a rejected configuration, so judge a job from GitHub or `_diag`.
- **Runner files stay pinned.** The default version is Actions Runner `2.338.2`
  for Linux x64 and arm64. The build verifies the matching release archive
  checksum before adding files at `/opt/actions-runner`.
- **Runner updates remain enabled.** JIT startup uses `run.sh`, which does not
  accept `--disableupdate` (a `config.sh` option). When GitHub requires a newer
  runner, the runner downloads it at job start, which adds time to every job
  until the `version`, `sha256_x64` and `sha256_arm64` arguments are bumped.
- **Long-running is optional.** Cloud sandboxes cannot provide
  `long-running@1` and live by their TTL; a local runtime that can provide it
  keeps the sandbox alive for the job.
- **Network access follows GitHub's documented runner requirements.** The
  runtime list covers essential operations, action downloads, runner updates,
  release downloads, and artifacts, logs and caches. Workflows that use GitHub
  Packages or container registries add `ghcr.io`, `*.pkg.github.com` and
  `pkg-containers.githubusercontent.com` at create time with `--allow-network`.
  Other workflow dependencies may need more hosts.

## Security

- Use one sandbox per job and remove the sandbox after the job.
- Do not run fork pull requests on this self-hosted runner; workflow code runs
  with the runner user's privileges.
