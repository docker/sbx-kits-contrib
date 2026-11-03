# syntax=docker/dockerfile:1

# Overlay recipe for the python mixin.
#
# Why not copy /usr/local out of the official python image: that interpreter
# links the build image's own libssl, libffi and libsqlite, so it breaks on a
# base with different ones. python-build-standalone is built to be relocated
# and is what `uv python install` fetches, so the build stage uses uv to get it
# and the overlay ships the tree.
#
# The kit's uvVersion arg always overrides this default. It exists only so the
# FROM lines below name a valid image when linted without build args; the
# version check in the build stage is what holds the pin.
ARG UV_VERSION=0.13.6
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM ghcr.io/astral-sh/uv:${UV_VERSION}-debian-slim AS build
ARG PYTHON_VERSION
ARG UV_VERSION
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN set -eu; \
    [ -n "${PYTHON_VERSION}" ] && [ -n "${UV_VERSION}" ] \
      || { echo "PYTHON_VERSION and UV_VERSION must be set" >&2; exit 1; }; \
    uv_banner="$(uv --version)"; \
    case "${uv_banner}" in \
      "uv ${UV_VERSION} "*|"uv ${UV_VERSION}") ;; \
      *) echo "pin mismatch: kit declares uv ${UV_VERSION}, uv reports '${uv_banner}'" >&2; exit 1 ;; \
    esac; \
    uv python install "${PYTHON_VERSION}"; \
    mv "$(dirname "$(dirname "$(uv python find "${PYTHON_VERSION}")")")" /opt/python; \
    /opt/python/bin/python3 -c "import sys, ssl, sqlite3, ctypes, venv; v = sys.version.split()[0]; assert v == '${PYTHON_VERSION}', 'pin mismatch: kit declares ${PYTHON_VERSION}, python reports ' + v"

# The overlay: one tree under /opt and two binaries, nothing under /home/agent.
FROM scratch
COPY --from=build /opt/python /opt/python
COPY --from=uv /uv /uvx /usr/local/bin/

# PATH merges by appending, so a python3 the base workload ships keeps
# precedence over this one.
ENV PATH=/opt/python/bin
