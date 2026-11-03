# syntax=docker/dockerfile:1

# Overlay recipe for the jdk mixin: one tree taken from the official image.
#
# The image tag is `<version>_<build>-jdk`. The build number is Adoptium's
# rebuild counter for a release, not part of the Java version, so it stays out
# of the kit's version and provide; bump it only when Adoptium publishes a
# rebuild of the same release.
ARG JDK_VERSION
ARG TEMURIN_BUILD=1
FROM eclipse-temurin:${JDK_VERSION}_${TEMURIN_BUILD}-jdk AS build
ARG JDK_VERSION
RUN set -eu; \
    [ -n "${JDK_VERSION}" ] || { echo "JDK_VERSION must be set" >&2; exit 1; }; \
    banner="$(/opt/java/openjdk/bin/java -version 2>&1 | head -1)"; \
    echo "java -version: ${banner}"; \
    case "${banner}" in \
      *"\"${JDK_VERSION}\""*) ;; \
      *) echo "pin mismatch: kit declares ${JDK_VERSION}, java reports '${banner}'" >&2; exit 1 ;; \
    esac

# The overlay: one tree under /opt, nothing under /home/agent.
FROM scratch
COPY --from=build /opt/java/openjdk /opt/java/openjdk

# JAVA_HOME is set by this kit alone. PATH merges by appending, so a JDK the
# base workload already ships keeps precedence over this one.
ENV JAVA_HOME=/opt/java/openjdk PATH=/opt/java/openjdk/bin
