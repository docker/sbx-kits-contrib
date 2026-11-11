# Mixin e2e workload

This private test fixture preserves the Ubuntu package database and apt
sources that contrib mixins expect from `shell-docker`. The DHI Shell
workload uses Debian and versioned Python packages, so substituting it
changes both requirement resolution and the hosts reached by apt hooks.

The fixture declares no credentials or network policy. Each tested mixin
must supply its own grants. Kit discovery scans only top-level directories,
so this fixture is neither cataloged nor published. Use `E2E_HOST` to test a
mixin against another workload, including DHI.
