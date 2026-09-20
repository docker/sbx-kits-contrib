## T3 Code

This sandbox has the build toolchain (`g++`, `make`, `python3`) and the
`t3` npm package pre-installed so T3 Code's SSH integration can connect
without compiling anything on first connect.

- `t3` is on PATH. T3 Code's remote bootstrap finds it directly instead
  of falling back to `npx --package t3@latest`, so the first connection
  does not depend on npm registry access or a slow from-source build.
- The toolchain exists only to satisfy `node-pty`, a t3 dependency that
  ships prebuilt binaries for macOS and Windows but not Linux. Removing
  `g++`, `make`, or `python3` breaks any future `npm install` or
  `npm rebuild` that touches `node-pty`.
