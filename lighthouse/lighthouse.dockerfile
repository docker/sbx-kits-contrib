# syntax=docker/dockerfile:1.7
# Lighthouse as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: the v2 kit had no Dockerfile because a v2 mixin
# had no content mechanism -- a lifecycle install hook was the only way for one
# to install anything. v3 lifts that, so the hooks that were pure content build
# here instead of at every sandbox create: the /etc/profile.d drop, the pinned
# npm install with its CLI wrapper, and the browser tree, which is a
# version-pinned artifact download that needs nothing from create time. What
# that buys is no per-create download, no npm registry and no browser CDN in the
# kit's permission surface at all, and content that is digest-pinned and
# scannable in the published kit.
#
# WHAT THIS OVERLAY CANNOT CARRY: the system libraries Chromium links against.
# `install --with-deps` apt-installs them, and apt packages are not copyable
# content -- they need the composed base's own dpkg database, and an overlay
# cannot carry a package's shared-library closure. So the download half of v2's
# third hook is here and the apt half stays a hook in lighthouse.yaml, run from
# the playwright-core this stage stages for it. ../playwright and
# ../openclaw-mixin split the same work the same way for the same reason.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# Lighthouse 13.x requires Node >= 22.19; standard agent templates only
# guarantee Node >= 18. 12.6.1 is the last 12.x line and accepts Node >= 18.20.
# npm verifies tarballs against registry sha512 integrity, so pinning the
# version pins the content. To bump: change this line, the `provides` entry in
# lighthouse.yaml, and the version in lighthouse-context.md / README. Do not
# jump to 13.x until templates ship Node 22.19.
ARG LIGHTHOUSE_VERSION=12.6.1
# The browser channel, pinned exactly as v2's `npx -y playwright@1.61.1` pinned
# it, and deliberately the same release ../playwright ships so both kits land
# the same Chromium revision at the shared path.
ARG PLAYWRIGHT_VERSION=1.61.1

# Root, matching the `user: "0"` the install hooks ran as.
USER root

# v2's second install hook. The proxy plumbing it carried is gone: the builder
# reaches registry.npmjs.org directly, so `npm config set proxy` has nothing to
# configure. The `command -v npm` guard is gone too -- a base without npm now
# fails this build rather than a user's sandbox, which is the point of the move.
# (Node itself still has to exist on the *composed* base at run time: this
# overlay ships lighthouse's JS, not an interpreter. That was true in v2 too.)
RUN npm install -g "lighthouse@${LIGHTHOUSE_VERSION}"

# playwright-core, in a private prefix rather than the global npm root, for two
# jobs: installing the browser below, and -- once composed -- computing
# Chromium's apt dependency list for the one hook that stays in lighthouse.yaml.
# Staging it is what keeps registry.npmjs.org out of the kit's install phase
# entirely; without it that hook would have to `npx -y playwright@...` at create
# and the npm registry would have to be reachable from the sandbox again.
#
# Private, because the global root is on NODE_PATH: a package the user never
# asked for should not become importable as a side effect. playwright-core has
# no browser-downloading postinstall (that is `playwright`'s), so this fetches
# the driver and nothing else.
RUN npm install --no-audit --no-fund --prefix /usr/local/lib/lighthouse-kit \
      "playwright-core@${PLAYWRIGHT_VERSION}"

# The download half of v2's third install hook. `--with-deps` even though the
# libraries it apt-installs are never copied out: playwright validates host
# requirements after the download and exits non-zero when they are missing, so a
# bare `install chromium` fails this build on the template base. The apt side is
# a build-stage side effect that dies with the stage.
#
# v2's hook skipped the download when a Chromium was already under
# /opt/ms-playwright -- a create-time look at the *composed* filesystem, to avoid
# fetching the browser twice when this kit and ../playwright are composed. A
# build cannot make that decision and no longer needs to: neither kit downloads
# anything at create any more, both pin playwright 1.61.1, so both overlays
# carry the same Chromium revision at the same path and the duplicate costs
# layer bytes rather than sandbox-create time.
RUN PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
      node /usr/local/lib/lighthouse-kit/node_modules/playwright-core/cli.js \
        install --with-deps chromium \
 && rm -rf /var/lib/apt/lists/*

# Stage the specific paths the installs produced.
RUN <<'EOF'
set -eux

# Asked for rather than hardcoded, so a template that moves its npm prefix fails
# this build instead of producing an overlay that lands nothing where NODE_PATH
# points. On the current templates both resolve under /usr/local/share/npm-global,
# which is the path the profile.d drop and the wrapper below name.
prefix="$(npm prefix -g)"
root="$(npm root -g)"

LH_JS="$root/lighthouse/cli/index.js"
test -f "$LH_JS"
test -f /usr/local/lib/lighthouse-kit/node_modules/playwright-core/cli.js

mkdir -p "/out${root}" "/out${prefix}/bin" \
         /out/usr/local/bin /out/usr/local/lib /out/opt

# lighthouse's dependency tree nests under the package itself in a global
# install, so this one tree is the whole closure.
cp -a "$root/lighthouse" "/out${root}/lighthouse"

# npm tarballs preserve the publisher's own uid and `cp -a` carries it in: this
# tree arrives owned by 1001:1001, 501:20 and 1001:127 across its dependencies.
# That was harmless while the install ran at create time against the real base,
# but as image content on an unknown base those ids may be real accounts, and a
# file's owner can rewrite it whatever its mode says. Normalized to root, which
# is what a root-run global install leaves anyway; the agent needs write access
# to the prefix directory below, not to lighthouse's own tree.
chown -R 0:0 "/out${root}/lighthouse"

# An overlay's directory entries override the base's, and the template base owns
# the global prefix root as agent:agent so the agent can `npm install -g`
# without sudo. mkdir made it root-owned; without this line the overlay would
# quietly take that away. Numeric because scratch carries no /etc/passwd. The
# lib/ and bin/ below it stay root-owned, which is what the root-run install
# hook left behind on a v2 sandbox.
chown 1000:1000 "/out${prefix}"

# The private playwright-core the apt hook drives. Same publisher-uid problem
# as the tree above, same normalization.
cp -a /usr/local/lib/lighthouse-kit /out/usr/local/lib/lighthouse-kit
chown -R 0:0 /out/usr/local/lib/lighthouse-kit

# v2's CLI wrapper, byte-for-byte: the same printf sequence the install hook
# used, so the shebang stays in column 0 and nothing in the body is expanded by
# the shell writing it.
#
# The three defaults are load-bearing and survive the move to build time
# unchanged. /etc/profile.d is sourced by login shells only, so a lighthouse
# started from anything else -- an agent tool call, a startup hook, a script --
# has not seen those exports, and chrome-launcher reading an unset CHROME_PATH
# goes looking for a host Chrome that is not in this sandbox. `: "${X:=default}"`
# assigns only when unset, so a value already in the environment (../playwright's,
# when both kits are composed) still wins.
{
  printf '%s\n' '#!/bin/sh' 'set -eu' 'has_flags=0'
  printf '%s\n' ': "${CHROME_PATH:=/usr/local/bin/chromium}"'
  printf '%s\n' ': "${PLAYWRIGHT_BROWSERS_PATH:=/opt/ms-playwright}"'
  printf '%s\n' ': "${NODE_PATH:=/usr/local/share/npm-global/lib/node_modules}"'
  printf '%s\n' 'export CHROME_PATH PLAYWRIGHT_BROWSERS_PATH NODE_PATH'
  printf '%s\n' 'for arg in "$@"; do'
  printf '%s\n' '  case "$arg" in' '    --chrome-flags|--chrome-flags=*) has_flags=1 ;;' '  esac'
  printf '%s\n' 'done'
  printf '%s\n' 'if [ "$has_flags" -eq 0 ]; then'
  # --headless is not optional here, and its absence was a real bug carried
  # over from v2: the sandbox has no display, so Playwright's Chromium refuses
  # to start and every audit died with "Unable to connect to Chrome" whether
  # the browser came from a create-time hook or from this layer. The other
  # three are the ordinary container flags -- no user namespace for --no-sandbox
  # to drop into, /dev/shm too small for Chromium's default, and no GPU.
  printf '%s\n' '  set -- "$@" --chrome-flags="--headless --no-sandbox --disable-dev-shm-usage --disable-gpu"'
  printf '%s\n' 'fi'
  printf '%s\n' "exec node \"${LH_JS}\" --no-enable-error-reporting \"\$@\""
} > /out/usr/local/bin/lighthouse
chmod 0755 /out/usr/local/bin/lighthouse

# npm's own bin entry, pointed at the wrapper as the v2 hook pointed it: both
# $prefix/bin and /usr/local/bin are on the template's PATH, and whichever wins
# has to be the wrapper or the container-safe Chrome flags are lost. Replaces
# the relative symlink npm created into lighthouse/cli/index.js.
ln -sfn /usr/local/bin/lighthouse "/out${prefix}/bin/lighthouse"

# The browser tree, and the stable name CHROME_PATH points at: the symlink
# absorbs the Chromium revision in the directory name so the exported path does
# not move when the pin changes. Resolved by search rather than spelled out, the
# same `find` the v2 hook used, so a revision bump needs no edit here. The target
# is the composed path, not the staging one.
chrome="$(find /opt/ms-playwright -type f -name chrome ! -path '*headless*' | head -1)"
test -n "$chrome"
test -x "$chrome"
cp -a /opt/ms-playwright /out/opt/ms-playwright
ln -sfn "$chrome" /out/usr/local/bin/chromium

# World-writable, which is a widening of v2's `chmod -R a+rX` and deliberate.
# ../playwright ships this same tree world-writable by design -- it keeps the
# browser CDNs in its runtime phase so a project pinning a different Playwright
# version can fetch its matching build here as uid 1000 -- and two overlays that
# disagree about a directory's mode resolve by layer order, silently revoking
# that when this one lands last. Identical layers compose in any order. It is
# not a boundary either way: the template's agent user is in the sudo group.
chmod -R 777 /out/opt/ms-playwright
EOF

# v2's `environment.variables`, and v3's first install hook, verbatim. A mixin's
# image config is not the composed image's, so these ride a profile.d snippet the
# base's login shell sources rather than ENV -- and the wrapper above defaults
# all three again for everything that is not a login shell.
COPY <<'EOF' /out/etc/profile.d/lighthouse-env.sh
# chrome-launcher reads CHROME_PATH (LIGHTHOUSE_CHROMIUM_PATH is deprecated).
# The overlay points this symlink at Playwright's chrome binary so the path
# stays stable across Chromium builds.
export CHROME_PATH=/usr/local/bin/chromium
# Same system path as the playwright kit, so composing both kits shares one
# browser tree.
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
# Lets `require('lighthouse')` / `import('lighthouse')` resolve from the global
# npm install in a workspace with no package.json. Projects with their own
# node_modules are unaffected.
export NODE_PATH=/usr/local/share/npm-global/lib/node_modules
EOF

# The overlay: the CLI, its wrapper, the browser tree and the environment,
# landing on any base. Nothing is staged under the agent's home -- /usr/local,
# /opt and /etc/profile.d are what a mixin landing on an unknown base should
# prefer, since whatever is at /home/agent may be a mounted volume. No
# ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
