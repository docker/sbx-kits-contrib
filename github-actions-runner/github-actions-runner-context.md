## GitHub Actions Runner

The Actions runner is installed at `/opt/actions-runner`. It starts only when
`RUNNER_JITCONFIG` is supplied, runs one job from that JIT configuration, and
will not reuse a configuration after startup. After the runner exits, its
`.runner`, `.credentials`, and `.credentials_rsaparams` files are removed.
Startup output is logged to `/tmp/actions-runner.log`; runner diagnostics are
written to `/opt/actions-runner/_diag`. The runner is managed by the dispatcher;
remove the sandbox after the job completes.
