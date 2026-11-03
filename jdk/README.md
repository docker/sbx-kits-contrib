# JDK

A mixin that adds a Java toolchain, Eclipse Temurin 25, to a workload that
ships none, such as `claude`. It copies the JDK out of the official
`eclipse-temurin` image into `/opt/java/openjdk` and sets `JAVA_HOME` and
`PATH`. Nothing lands in the agent's home.

## Usage

```sh
sbx run docker.io/sbx/claude:latest --kit docker.io/sbx/jdk:latest .
```

From git, or from a local checkout:

```sh
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#ref=main&dir=jdk" .
sbx run ./claude --kit ./jdk .
```

Inside the sandbox, `java -version` reports the kit's version.

## How it works

- **Copied, not installed.** A JDK is a relocatable tree, so a multi-stage
  build takes `/opt/java/openjdk` from the upstream image and a `FROM scratch`
  stage ships only that directory. No package manager state travels with it,
  and it lands on any glibc base.
- **The version is enforced.** The `version` arg picks the image tag, and the
  build fails unless the copied `java -version` reports exactly that version,
  so `provides: jdk@<version>` is a claim about the content.
- **No network policy.** The kit adds no hosts. A build tool that downloads
  dependencies (Maven, Gradle) needs its repositories allowed by the workload
  or another kit.
- **A base JDK wins.** `PATH` merges by appending, so on a workload that ships
  its own Java, that one stays first.
