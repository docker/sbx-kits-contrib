## T3 Code

This sandbox has the `t3` npm package pre-installed and on PATH.

- T3 Code's remote bootstrap finds `t3` directly instead of falling back
  to `npx --package t3@latest`, so the first connection does not reach
  the npm registry.
- `t3` ships prebuilt native modules (`node-pty` among them), so nothing
  compiles here. Those binaries need `libatomic1`, which this kit installs
  when the base image lacks it.
- The t3 server's anonymous usage telemetry is off in this sandbox unless
  the kit was installed with `telemetry=true`.
