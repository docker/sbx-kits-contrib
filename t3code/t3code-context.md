## T3 Code

This sandbox has a `t3` release pre-installed for T3 Code's SSH integration:
the release this kit was built with, at `/opt/t3code/runtime/versions/<version>/`.

- T3 Code's remote bootstrap runs the release matching the connecting
  app from `~/.t3/runtime/versions/<version>/`. The pre-installed release is
  linked there already; a newer app downloads its own release into a sibling
  directory on first connection.
- Those binaries need `libatomic1`, which this kit installs when the base
  image lacks it.
- The t3 server's anonymous usage telemetry is off in this sandbox unless
  the kit was installed with `telemetry=true`.
