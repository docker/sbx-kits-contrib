# syntax=docker/dockerfile:1.7
# Playwright as an overlay.
#
# WHY THIS FILE EXISTS AT ALL: the v2 kit had no Dockerfile because a v2 mixin
# had no content mechanism -- a lifecycle install hook was the only way for one
# to install anything. v3 lifts that, so the two hooks that were pure content
# (the /etc/profile.d drop and the pinned npm install) and the browser half of
# the third are built here instead of at every sandbox create. What that buys:
# no per-create download, no npm registry or browser CDN in the kit's
# install-phase permission surface, content that is digest-pinned in the
# published kit and scannable there, and a broken install that fails at publish
# instead of in a user's sandbox.
#
# WHAT THIS OVERLAY CANNOT CARRY: the system libraries Chromium links against.
# `playwright install --with-deps` apt-installs them, and apt packages are not
# copyable content -- they need the composed base's own dpkg database, and an
# overlay cannot carry a package's shared-library closure. The browser tree
# therefore travels in this overlay and the libraries stay an install hook in
# playwright.yaml; ../openclaw-mixin documents the same split for the same
# reason. A composed sandbox gets the binaries at compose time and pays one apt
# run at create. On a base that is not Debian-family, or with the apt hosts
# blocked, Chromium is present and does not launch.
#
# The build stage is the workload's own base rather than a relocating install,
# which is the shape the migration guide prescribes for an install that takes no
# relocation flag: npm's global prefix and Playwright's browsers path are both
# absolute, and everything below lands at the absolute path it was built at, so
# npm's relative bin symlink keeps resolving once the overlay is composed.
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE} AS build

# The pin the install hook carried as a literal, unchanged. Stated here rather
# than promoted to a kit arg deliberately -- npm verifies the tarballs against
# the registry metadata's sha512 integrity values, so this version is a fact
# about what the kit ships, not a knob. To bump: edit this line, the `provides`
# entry in playwright.yaml, playwright-context.md and the README together.
ARG PLAYWRIGHT_VERSION=1.61.1

# Root, matching the `user: "0"` the install hooks ran as, so the tree this
# stages is the tree they produced.
USER root

# v2's second install hook, verbatim apart from the proxy plumbing it needed
# only inside a sandbox: the builder reaches registry.npmjs.org directly, so
# `npm config set proxy` has nothing to configure here. The `npm -v` guard the
# hook carried is likewise gone -- a base without npm fails this build rather
# than a user's sandbox, which is the point of moving it.
RUN npm install -g "playwright@${PLAYWRIGHT_VERSION}" "@playwright/test@${PLAYWRIGHT_VERSION}" \
 && playwright --version

# The browser half of v2's third install hook.
#
# `--with-deps` even though the libraries it apt-installs are never copied out:
# playwright validates host requirements after the download and exits non-zero
# when they are missing, so a bare `install chromium` fails this build on the
# template base. The apt side is a build-stage side effect that dies with the
# stage; only /opt/ms-playwright is staged.
#
# World-writable, as the official Playwright image and the v2 hook both leave
# it: the descriptor keeps the browser CDNs in its runtime phase so a project
# pinning a different Playwright version can fetch its matching build into this
# same directory as uid 1000.
RUN PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install --with-deps chromium \
 && chmod -R 777 /opt/ms-playwright \
 && rm -rf /var/lib/apt/lists/*

# Stage the specific paths the two installs produced.
RUN <<'EOF'
set -eux

# Asked for rather than hardcoded, so a template that moves its npm prefix
# fails this build instead of producing an overlay that lands nothing where
# NODE_PATH points. On the current templates both resolve under
# /usr/local/share/npm-global, which is the path the profile.d drop names.
prefix="$(npm prefix -g)"
root="$(npm root -g)"

# Three assertions for three independently movable things. A missing one is
# invisible at build time and fatal at run time.
test -d "$root/playwright"
test -d "$root/@playwright/test"
test -e "$prefix/bin/playwright"

mkdir -p "/out${root}" "/out${prefix}/bin" /out/opt /out/usr/local/bin

# playwright-core rides inside playwright/node_modules, so these two trees are
# the whole closure; npm's .package-lock.json is deliberately not copied, being
# bookkeeping for a global tree this overlay only adds to.
cp -a "$root/playwright"  "/out${root}/playwright"
cp -a "$root/@playwright" "/out${root}/@playwright"
# A relative symlink into the tree above (../lib/node_modules/@playwright/test/
# cli.js), so it travels as a symlink and resolves inside the overlay.
cp -a "$prefix/bin/playwright" "/out${prefix}/bin/playwright"

# An overlay's directory entries override the base's, and the template base owns
# the global prefix root as agent:agent so the agent can `npm install -g`
# without sudo. mkdir made it root-owned; without this line the overlay would
# quietly take that away. Numeric because scratch carries no /etc/passwd. The
# lib/ and bin/ below it stay root-owned, which is what the root-run install
# hook left behind on a v2 sandbox.
chown 1000:1000 "/out${prefix}"

# /usr/local/bin/playwright, the symlink the v2 hook made with
# `ln -sf "$(command -v playwright)"`. Not redundant: $prefix/bin is on PATH
# only because *this* base puts it there, and an overlay lands on a base that
# may not. Absolute, because a copy of npm's relative link would resolve
# against /usr/local/lib from here.
ln -sf "$prefix/bin/playwright" /out/usr/local/bin/playwright

cp -a /opt/ms-playwright /out/opt/ms-playwright
EOF

# v2's `environment.variables`, and v3's first install hook. A mixin's image
# config is not the composed image's, so these ride a profile.d snippet the
# base's login shell sources rather than ENV. Nothing in the overlay depends on
# the file being sourced: the browsers are staged at the path it names, and the
# remaining apt hook does not read it.
COPY <<'EOF' /out/etc/profile.d/playwright-env.sh
# Installed by sbx-kits-contrib/playwright. See playwright.yaml for why each of
# these is a fixed path rather than a tunable.
export NODE_PATH=/usr/local/share/npm-global/lib/node_modules
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
EOF

# The overlay: the CLI, the test runner, the browser tree and the environment,
# landing on any base. Nothing is staged under the agent's home -- /usr/local,
# /opt and /etc/profile.d are what a mixin landing on an unknown base should
# prefer, since whatever is at /home/agent may be a mounted volume. No
# ENTRYPOINT -- the base workload's launch command stays.
FROM scratch
COPY --from=build /out /
