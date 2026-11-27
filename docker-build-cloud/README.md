> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# docker-build-cloud

A mixin that makes the sandbox's `docker build` and `docker buildx build` run on
a [Docker Build Cloud](https://docs.docker.com/build-cloud/) builder instead of
the sandbox's own Docker Engine. It authenticates as the user logged in to `sbx`
on the host, and the Docker credential never enters the sandbox.

It depends on one workaround, a small loopback shim, because of how buildx
authenticates to Docker Hub. [Why there is a shim](#why-there-is-a-shim) explains
it, and [Security](#security) says what the kit does and does not protect.

## Prerequisites

- A builder created in the [Docker Build Cloud dashboard](https://app.docker.com/build/).
  The kit connects to an existing builder; it cannot create one.
- You are logged in to `sbx` on the host, as an account that can use the builder.
  The kit uses the `sbx-login` credential service, so there is no secret to set
  and no token to paste.
- A base with Docker's CLI and buildx 0.37.0 or later, and `python3`, such as the
  shell workload. The kit requires `deb/docker-ce`, so composition fails up
  front on a base without Docker. It cannot require `python3` the same way,
  because `deb/python3` is not among the provides derived for the shell and
  claude-code bases, so a base without it fails at the install hook instead.
  buildx's version is checked when the sandbox is created.

## Usage

One arg is required, namespaced by the kit name:

| Arg | What it is | Example |
| --- | --- | --- |
| `builder` | The builder as `ORG/NAME`, as in `docker buildx create --driver cloud ORG/NAME` | `acme/default` |

```console
sbx run \
    --kit docker.io/sbx/docker-build-cloud:latest \
    --kit-arg docker-build-cloud.builder=acme/default \
    shell
```

Or directly from this repository:

```console
sbx run \
    --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=docker-build-cloud" \
    --kit-arg docker-build-cloud.builder=acme/default \
    shell
```

Or from a local clone:

```console
sbx run \
    --kit ./docker-build-cloud \
    --kit-arg docker-build-cloud.builder=acme/default \
    shell
```

Kit v3 needs an `sbx` release candidate or nightly build from
[docker/sbx-releases](https://github.com/docker/sbx-releases/releases); the
stable line does not load v3 kits.

Inside the sandbox, builds go to Build Cloud without any flag:

```console
docker buildx ls                              # cloud-acme-default is the default builder
docker build -t myapp .
docker buildx build --push -t acme/myapp:dev .
docker buildx build --load -t myapp .         # bring the image back into the sandbox's engine
docker buildx build --builder default .       # opt out: build on the local engine
```

## What the kit does

Docker Build Cloud is a buildx *driver*, not a Docker Engine setting, so the kit
configures the Docker CLI's side (`~/.docker`) and leaves dockerd alone. It has
six parts:

- **A proxy-managed credential on `sbx-login`**, for the install and runtime
  phases. The sandbox's Docker config
  holds a placeholder, and `DOCKER_ACCESS_TOKEN` holds the same sentinel. The
  proxy replaces the `Authorization` header with a `Bearer` of the host's login
  on requests to `hub.docker.com` and `auth.docker.io`. It is deliberately not
  injected on `build-cloud.docker.com`, whose Bearer is a build token that buildx
  gets back from `auth.docker.io`.
- **A network policy.** At runtime: `build-cloud.docker.com` (the builder's gRPC
  endpoint and registry), `auth.docker.io` and `hub.docker.com`. At install:
  `hub.docker.com`, which the builder lookup calls, and `auth.docker.io`, which
  is allowed because the credential injects on it and a credential in the install
  phase needs each of its inject domains allowed there. Docker's
  firewall guidance also lists the IP `3.211.38.21`, which is
  `build-cloud.docker.com`'s address and so reached by name. The registries a
  build pulls from and pushes to are reached by the builder, not the sandbox, and
  are not in this policy. The shim listens on loopback and needs no entry.
- **A helper with a shim.** `/usr/local/lib/docker-build-cloud/helper.py` is the
  kit's only file: standard-library Python, started on `127.0.0.1:8099` at every
  boot.
- **An install hook, which creates the builder.** At sandbox create it checks for
  buildx 0.37.0 or later, writes the placeholder login into
  `~/.docker/config.json` (merged into any config already there), runs the shim
  for its own duration, and runs
  `docker buildx create --driver cloud --use --driver-opt internal.hub.host=http://127.0.0.1:8099 ORG/NAME`.
  If that fails, because the builder name is wrong, the account cannot use it, or
  the login has expired, the hook exits non-zero with buildx's error and sandbox
  creation fails. Builds therefore never quietly fall back to the local engine.
- **Startup hooks, which repair.** At every boot one starts the shim in the
  background, and another runs the same setup against it: it selects the builder
  with `docker buildx use`, or creates it again if it is missing, which can
  happen if the agent's home is a volume that did not exist at install. These
  cannot stop the sandbox, because `sbx` logs a failing startup hook and boots
  anyway. The output is in `/var/log/sbx-kit-startup.log`.
- **Agent context.** A short note telling the agent that builds run on the cloud
  builder, how to use `--load` and `--push`, how to opt out, and not to touch the
  helper.

## Why there is a shim

buildx's cloud driver makes several requests to set up and use a builder, and it
reads one entry from `~/.docker/config.json` for all of them:
`auths["https://index.docker.io/v1/"]`. The sandbox proxy can add or replace
**headers** on requests to a host. That covers most of the flow, and it fails on
exactly one request.

| Step | Request | Credential is carried in | How it is handled |
| --- | --- | --- | --- |
| 1a | `POST hub.docker.com/v2/auth/token`, with JSON `identifier` and `secret` | The **request body** | **The shim** answers with a dummy token |
| 1b | `GET hub.docker.com/v2/cloud-builds/accounts/ORG/builder-groups/NAME/instances` | `Authorization: Bearer` | The shim forwards it with no credential, and the proxy injects the login |
| 3 | `GET build-cloud.docker.com/v2/` health check | none | Nothing needed |
| 4 | `GET auth.docker.io/token?service=build.docker.com&scope=builder:…` | HTTP Basic | The proxy replaces it with a Bearer of the login |
| 5 | gRPC to `build-cloud.docker.com:443` | `Bearer` with the build token from step 4 | Nothing: buildx minted that token itself |
| 6 | Registry token requests for pulls and pushes | HTTP Basic | The proxy replaces it with a Bearer of the login |

Steps 1 and 4 are independent logins from the same config entry. A Hub token from
step 1 does nothing for step 4, and buildx repeats both whenever it resolves the
builder: on `create`, `ls` and every build.

**Step 1a is the problem.** Hub validates the body of that request. It rejects a
short `identifier` with a 400 and the placeholder `secret` with a 401, and an
injected `Authorization` header does not stand in for the body. The proxy cannot
rewrite bodies.

**But step 1a only mints a token that nothing needs.** buildx uses its answer as
the Bearer for step 1b, and the proxy replaces that Bearer with the real one
anyway. The kit therefore does not authenticate step 1a. It steps around it:
buildx has a driver option, `internal.hub.host`, that moves the Hub host used for
steps 1a and 1b. The kit points it at the shim, which

1. answers `POST /v2/auth/token` with a dummy `access_token`, discarding the body;
2. forwards `GET /v2/cloud-builds/...` to `https://hub.docker.com` through the
   sandbox proxy, with **no** `Authorization` header, so the proxy adds the real
   one;
3. refuses everything else.

Nothing secret passes through the shim, and it keeps none.

Other ways to solve this exist, and the shim is the one that works today with
only the sandbox's existing features:

| Approach | Why not |
| --- | --- |
| The proxy substitutes the sentinel in request bodies | Not a proxy feature. And the `sbx-login` token looks like a Hub JWT, which that endpoint may not accept as a `secret`. |
| sbx answers the Hub token exchange itself, or accepts a ready token | The clean fix, and it needs platform work. The shim can then go. |
| Put a real access token in the sandbox and run `docker login`, as [Docker's CI guide](https://docs.docker.com/build-cloud/ci/) does | It works, and the agent can read the token. |

## Security

- **The credential stays on the host.** The sandbox holds only the placeholder
  `sbx-login:proxy-managed`, in `~/.docker/config.json` and in
  `DOCKER_ACCESS_TOKEN`.
- **The injection is by domain.** The proxy adds the login's Bearer to **every**
  request the sandbox sends to `hub.docker.com` and `auth.docker.io`, not only the
  ones buildx makes. Anything running in the sandbox, the agent included, can act
  as the logged-in user on those two hosts, within what the token allows. That
  includes calling Hub's API and fetching registry tokens for any repository the
  user can reach. The shim does not widen this, since a plain `curl` gets the same
  injection. A path-scoped inject rule in sbx would narrow it. If that is
  unacceptable, do not use this kit.
- **The shim is narrow.** It listens on `127.0.0.1` only. It forwards `GET` under
  `/v2/cloud-builds/` to `hub.docker.com` and nothing else, rejecting `..`,
  encoded `/` and `..`, empty segments and other paths. It never forwards a
  caller's headers. It does not log headers or bodies, and the body of the token
  request is read and dropped.
- **The dummy token is not a secret** and is accepted by nothing: Hub never
  sees it, because the shim does not forward it.
- **The placeholder login is a stand-in.** It is also what buildx sends to the
  builder for registry access, which works because buildx fetches registry tokens
  in the sandbox, through the proxy.

## Verified, and not

The kit was tested in a real sandbox against a real builder. These all worked:

- creating the builder, in the install hook, with two running nodes
  (`linux-arm64`, `linux-amd64`), and making it the default. That shows
  `sbx-login` is available during install;
- a build from `scratch`, a build from a public base image, and a build from a
  **private** base image;
- `--load`, which pulls the result into the sandbox's engine;
- `--push` to a Docker Hub repository;
- a wrong builder name failing sandbox creation, with buildx's error;
- the builds showing in the Docker Build Cloud web app's history;
- the individual requests: the builder lookup, the build token for the builder
  scope, the health endpoint over HTTP/2, and a gRPC `Info` call with the build
  token, through the proxy's tunnel.

An earlier version created the builder in a startup hook. That showed a startup
hook that exits non-zero, which a wrong builder name causes, is logged as
`fail ... exit=1` and does **not** stop the sandbox: the builder was simply absent
from `docker buildx ls`. That is why the builder is created by an install hook.

The kit's own build runs the helper's self-test on a fresh base as the agent user
with no network, and exports the overlay from that stage so the test cannot be
skipped. It checks the shim's routes and its path filtering, that nothing is
forwarded for refused requests, that a caller's `Authorization` header is
dropped, the Docker config merge, and each way `setup` can end, against a stub
`docker`.

Not tested:

- How long the `sbx-login` token lives, and whether the proxy refreshes it. buildx
  refetches its build token about once a minute, so the login has to stay valid
  for the whole build.

## Limitations

- **buildx internals.** `internal.hub.host` is an internal, undocumented buildx
  driver option, and this kit relies on it. A buildx release could rename or
  remove it. Re-test the kit when the buildx version in the base changes. If the
  option goes away, builder creation fails when the sandbox is created, with
  buildx's error.
- **The shim has to be running.** buildx stores the option with the builder and
  calls the shim whenever it resolves the builder. If the shim is down,
  `docker build` fails with a connection error to `127.0.0.1:8099`. The startup
  hook starts it on every boot.
- **Port 8099.** The shim needs it free on loopback. If another process holds it,
  the hook fails and says so.
- **One builder.** The kit configures one builder per sandbox.
- **Only the lookup is checked at create.** The hook proves that Hub resolves the
  builder for this login. The build token from `auth.docker.io` and the gRPC
  connection are first used by a build, so a failure there shows up at the first
  `docker build`.
- **Creation needs the login.** The install hook calls Hub, so creating the
  sandbox needs an `sbx` login that can use the builder, and network access to
  `hub.docker.com`. A sandbox cannot be created offline with this kit.
- **A boot-time failure is only logged.** If the shim or the builder selection
  fails at a later start, the sandbox boots, and builds fail or run locally. The
  startup log says why.

## Troubleshooting

The sandbox is not created, which is the install hook failing. `sbx` prints the
hook's output, which is buildx's own error followed by a message naming the
builder. The common ones:

| Error | Likely cause |
| --- | --- |
| `failed to fetch hub token ... 401` | The shim is not in use, or Hub rejected the request. Check that the builder was created with `internal.hub.host`, with `docker buildx inspect`. |
| `no builders found for group` | The builder name is wrong, or the account cannot see it. |
| `no credentials found` | The placeholder login is missing from `~/.docker/config.json`. |
| `the Docker Hub shim is not answering` | The shim failed to start. Read `/tmp/docker-build-cloud-shim.log`. |
| `buildx ... is too old` | The base's buildx is older than 0.37.0. |

The sandbox starts but builds fail or run locally, which is a boot-time failure.
Startup hooks cannot stop the sandbox, so read their log:

```console
sbx exec <sandbox> cat /var/log/sbx-kit-startup.log
```

Then check each piece:

```console
curl -s http://127.0.0.1:8099/healthz              # the shim: expect "docker-build-cloud shim"
docker buildx ls                                   # the builder and its nodes should be running
sbx policy log <sandbox>                           # on the host: what the proxy allowed and injected
```

To check the helper itself, from a clone of this repository:

```console
python3 docker-build-cloud/files/helper.py self-test
```

## Files

| File | What it is |
| --- | --- |
| `docker-build-cloud.yaml` | The descriptor: the credential, network policy, hooks and agent context |
| `docker-build-cloud.dockerfile` | The recipe: stages the helper and runs its self-test |
| `files/helper.py` | The shim, the Docker config merge and the self-test, standard-library Python |
