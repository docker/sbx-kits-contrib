## T3 Code

This sandbox is prepared for T3 Code's SSH integration.

- On first connection, T3 Code downloads the exact `t3` release that
  matches the connecting app into `~/.t3/runtime/versions/<version>/`
  and runs it from there. Nothing is pre-installed, so the server
  always matches the app that connected.
- Those binaries need `libatomic1`, which this kit installs when the base
  image lacks it.
- The t3 server's anonymous usage telemetry is off in this sandbox unless
  the kit was installed with `telemetry=true`.
