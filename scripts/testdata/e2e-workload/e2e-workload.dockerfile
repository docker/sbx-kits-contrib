# syntax=docker/dockerfile:1
# Keep the package database and apt sources used by the contrib mixins.
FROM docker/sandbox-templates:shell-docker
USER agent
ENTRYPOINT ["bash", "-l"]
