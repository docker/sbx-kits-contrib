#!/bin/sh
# cosmos-emulator: runs and inspects the Azure Cosmos DB emulator (vNext, API
# for NoSQL) on the sandbox's own Docker Engine. Shipped by the
# cosmos-db-emulator kit, whose startup hook runs `cosmos-emulator boot` in the
# background on every sandbox start. `cosmos-emulator help` lists the commands.
set -u

: "${PATH:=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

CONTAINER=cosmos-emulator
VOLUME=cosmos-emulator-data
CERT_VOLUME=cosmos-emulator-cert
REPOSITORY=mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator
STATE_FILE=/run/cosmos-db-emulator.state
BOOT_LOG=/var/log/cosmos-db-emulator.log
TRUSTED_CERT=/usr/local/share/ca-certificates/cosmos-db-emulator.crt
# Where the emulator container finds this sandbox's https certificate. The PFX
# password guards nothing -- the file never leaves the sandbox's Docker -- but
# the emulator wants one.
CERT_MOUNT=/cosmos-db-emulator-cert
PFX_PASSWORD=cosmos-db-emulator
GATEWAY_PORT=8081
EXPLORER_PORT=1234
HEALTH_PORT=8080
# The emulator's documented account key. The kit sets it as image ENV; this
# copy covers a process that ENV did not reach (sudo resets the environment).
WELL_KNOWN_KEY='C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=='

key=${COSMOS_EMULATOR_KEY:-$WELL_KNOWN_KEY}
protocol=
tag=
image=
stamp=0

say() {
  if [ "$stamp" = 1 ]; then
    printf '%s cosmos-emulator: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
  else
    printf 'cosmos-emulator: %s\n' "$*" >&2
  fi
}

die() {
  say "$*"
  exit 1
}

is_count() {
  case ${1:-} in
    '' | *[!0-9]*) return 1 ;;
  esac
}

# Single-quotes a value for the `env` command's eval-able output.
quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

docker_up() { timeout 10 docker info >/dev/null 2>&1; }

need_docker() {
  command -v docker >/dev/null 2>&1 ||
    die "docker not found; this kit needs a Docker-in-Docker base such as docker.io/docker/sbx-kit-shell"
  docker_up || die "the Docker daemon is not reachable: $(docker info 2>&1 >/dev/null | tail -n 1)"
}

wait_docker() {
  deadline=$(($(date +%s) + $1))
  until docker_up; do
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 1
  done
}

exists() { docker container inspect "$CONTAINER" >/dev/null 2>&1; }
state() { docker container inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null; }
running() { [ "$(state)" = running ]; }
container_image() { docker container inspect -f '{{.Config.Image}}' "$CONTAINER" 2>/dev/null; }
container_image_id() { docker container inspect -f '{{.Image}}' "$CONTAINER" 2>/dev/null; }
container_env() {
  docker container inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" 2>/dev/null |
    sed -n "s/^$1=//p"
}

# The settings to run with: the kit args when they reached this process,
# otherwise whatever the existing container already runs, otherwise the kit's
# defaults. Falling back to the container keeps `sudo cosmos-emulator start`,
# which drops the args, from recreating the emulator over different settings.
resolve_config() {
  protocol=${COSMOS_EMULATOR_PROTOCOL:-}
  tag=${COSMOS_EMULATOR_IMAGE_TAG:-}
  if { [ -z "$protocol" ] || [ -z "$tag" ]; } && exists; then
    [ -n "$protocol" ] || protocol=$(container_env PROTOCOL)
    if [ -z "$tag" ]; then
      ref=$(container_image)
      case $ref in
        "$REPOSITORY":*) tag=${ref#"$REPOSITORY":} ;;
      esac
    fi
  fi
  protocol=${protocol:-http}
  tag=${tag:-vnext-latest}
  image=$REPOSITORY:$tag
  case $protocol in
    http | https) ;;
    *)
      say "protocol must be http or https, not '$protocol'"
      return 1
      ;;
  esac
  # The `imageTag` arg's pattern, for a value set by hand.
  case $tag in
    vnext- | vnext-*[!A-Za-z0-9._-]*)
      say "image tag must be a vnext-* tag, not '$tag'"
      return 1
      ;;
    vnext-*) ;;
    *)
      say "image tag must be a vnext-* tag, not '$tag'"
      return 1
      ;;
  esac
}

effective_protocol() {
  p=$(container_env PROTOCOL)
  printf '%s\n' "${p:-${protocol:-${COSMOS_EMULATOR_PROTOCOL:-http}}}"
}

endpoint() { printf '%s://localhost:%s/\n' "$(effective_protocol)" "$GATEWAY_PORT"; }

# True when the existing container no longer matches the settings: another
# image tag or protocol, an https certificate that is not this sandbox's or is
# about to expire, or the tag was pulled again since it was created.
drifted() {
  exists || return 1
  current=$(container_image)
  if [ "$current" != "$image" ]; then
    drift="it runs $current, not $image"
    return 0
  fi
  current=$(container_env PROTOCOL)
  if [ "$current" != "$protocol" ]; then
    drift="it serves ${current:-the image default}, not $protocol"
    return 0
  fi
  if [ "$protocol" = https ]; then
    if [ "$(container_env CERT_PATH)" != "$CERT_MOUNT/emulator.pfx" ]; then
      drift="it serves the image's built-in certificate"
      return 0
    fi
    if running && ! docker exec "$CONTAINER" openssl x509 -checkend 2592000 -noout \
      -in "$CERT_MOUNT/tls.crt" >/dev/null 2>&1; then
      drift="its https certificate expires within 30 days"
      return 0
    fi
  fi
  local_id=$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null) || return 1
  if [ "$local_id" != "$(container_image_id)" ]; then
    drift="$image was pulled again since it was created"
    return 0
  fi
  return 1
}

# The health probe is published on an ephemeral loopback port, so nothing on
# the host can see it and it never collides with another kit's port 8080.
health_addr() { docker port "$CONTAINER" "$HEALTH_PORT/tcp" 2>/dev/null | head -n 1; }

health_get() {
  addr=$(health_addr)
  [ -n "$addr" ] || return 1
  curl -fsS --noproxy '*' --max-time 5 "http://$addr/$1" 2>/dev/null ||
    curl -fsSk --noproxy '*' --max-time 5 "https://$addr/$1" 2>/dev/null
}

ready() { health_get ready >/dev/null; }

boot_state() { head -n 1 "$STATE_FILE" 2>/dev/null; }

set_state() {
  { printf '%s\n' "$1" >"$STATE_FILE.tmp" && mv -f "$STATE_FILE.tmp" "$STATE_FILE"; } 2>/dev/null
}

pull() {
  docker image inspect "$image" >/dev/null 2>&1 && return 0
  say "pulling $image (a ~0.6 GB download, 2.3 GB on disk; once per sandbox)"
  docker pull --quiet "$image" >/dev/null
}

# The image's single-path entrypoint, or nothing when it has another shape.
image_entrypoint() {
  ep=$(docker image inspect -f '{{json .Config.Entrypoint}}' "$image" 2>/dev/null)
  case $ep in
    '["/'*'"]')
      ep=${ep#'["'}
      ep=${ep%'"]'}
      ;;
    *) return 1 ;;
  esac
  case $ep in
    *'"'* | *\\*) return 1 ;;
  esac
  printf '%s\n' "$ep"
}

# Data Explorer stays on http whatever the gateway serves: it is for a browser
# on the host, and it reaches the gateway through its own proxy, which does not
# check the certificate. NODE_EXTRA_CA_CERTS is for its start-up probe of the
# gateway, which does, and would log a certificate error on every start. It is
# started with `npm start`, whose update check would call registry.npmjs.org
# from every new container; NPM_CONFIG_UPDATE_NOTIFIER turns that off.
#
# Every start of the container first removes the postmaster.pid that a run
# killed before Postgres stopped -- `docker rm --force`, or a sandbox stopping
# under it -- leaves in the data volume. The container's processes get much
# the same low PIDs on every start, so the stale PID can be a live process's,
# and Postgres then refuses to start: the emulator never gets ready. Nothing
# else can be using the volume while the container starts.
create() {
  set -- --env "PROTOCOL=$protocol" --env EXPLORER_PROTOCOL=http --env ENABLE_TELEMETRY=false \
    --env NPM_CONFIG_UPDATE_NOTIFIER=false
  if [ "$protocol" = https ]; then
    set -- "$@" --volume "$CERT_VOLUME:$CERT_MOUNT:ro" \
      --env "CERT_PATH=$CERT_MOUNT/emulator.pfx" --env "CERT_SECRET=$PFX_PASSWORD" \
      --env "NODE_EXTRA_CA_CERTS=$CERT_MOUNT/tls.crt"
  fi
  if entry=$(image_entrypoint); then
    # shellcheck disable=SC2016 # expanded by the container's shell
    set -- "$@" --entrypoint /bin/sh "$image" \
      -c 'rm -f /data/db/postmaster.pid; exec "$@"' cosmos-emulator "$entry"
  else
    set -- "$@" "$image"
  fi
  docker run --detach --name "$CONTAINER" \
    --restart unless-stopped \
    --label com.docker.sandbox.kit=cosmos-db-emulator \
    --publish "$GATEWAY_PORT:8081" \
    --publish "$EXPLORER_PORT:1234" \
    --publish "127.0.0.1::$HEALTH_PORT" \
    --volume "$VOLUME:/data" \
    "$@" >/dev/null
}

# This sandbox's own https certificate: self-signed for localhost, 127.0.0.1
# and ::1, not a CA, kept in a volume of its own and renewed with under 30 days
# left. The image ships a certificate, but the private keys of it and of its
# root CA are in every copy of the public image, and .NET rejects it unless
# that root is trusted too. The image's openssl makes it; the sandbox may have
# none.
make_cert() {
  docker run --rm --user 0 --network none --entrypoint /bin/sh \
    --volume "$CERT_VOLUME:/cert" "$image" -c '
      set -e
      cd /cert
      if [ -s emulator.pfx ] && openssl x509 -checkend 2592000 -noout -in tls.crt >/dev/null 2>&1; then
        exit 0
      fi
      trap "rm -f tls.key req.cnf req.err tls.crt.new emulator.pfx.new" EXIT
      printf "%s\n" "[req]" "distinguished_name = dn" "prompt = no" "x509_extensions = ext" \
        "[dn]" "O = Cosmos DB emulator (sandbox-local)" "CN = localhost" \
        "[ext]" "basicConstraints = critical, CA:FALSE" "extendedKeyUsage = serverAuth" \
        "subjectAltName = DNS:localhost, IP:127.0.0.1, IP:::1" "subjectKeyIdentifier = hash" >req.cnf
      openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 825 -config req.cnf \
        -keyout tls.key -out tls.crt.new 2>req.err || { cat req.err >&2; exit 1; }
      openssl pkcs12 -export -inkey tls.key -in tls.crt.new -out emulator.pfx.new -passout "pass:$1"
      chmod 0644 tls.crt.new emulator.pfx.new
      mv -f emulator.pfx.new emulator.pfx
      mv -f tls.crt.new tls.crt' sh "$PFX_PASSWORD" >/dev/null
}

# Makes the emulator container exist, match the settings, and run. The data
# volume outlives every recreate; only `reset` removes it.
ensure() {
  if exists; then
    if drifted; then
      say "recreating the emulator container: $drift (the data volume stays)"
      # Stopped first, so that Postgres shuts down rather than being killed.
      docker stop "$CONTAINER" >/dev/null 2>&1
      docker rm --force "$CONTAINER" >/dev/null || return 1
    elif running; then
      return 0
    else
      say "starting the existing emulator container"
      docker start "$CONTAINER" >/dev/null
      return
    fi
  fi
  pull || return 1
  if [ "$protocol" = https ] && ! make_cert; then
    say "could not make the emulator's https certificate"
    return 1
  fi
  create && return 0
  # Another caller created it first, or it was created but could not start.
  exists && docker start "$CONTAINER" >/dev/null
}

# 0 ready, 1 timed out, 2 the container stopped, 3 the container is gone. A
# daemon that stops answering -- another kit restarting dockerd, say -- is
# waited out rather than taken for a missing container.
wait_ready() {
  deadline=$(($(date +%s) + $1))
  while :; do
    ready && return 0
    case $(state) in
      exited | dead) return 2 ;;
      '') docker_up && ! exists && return 3 ;;
    esac
    [ "$(date +%s)" -lt "$deadline" ] || return 1
    sleep 2
  done
}

# Trusting the certificate after every start keeps protocol=https working
# whatever happened in between: a switch from http, a renewed certificate, a
# trust store that lost it. When nothing changed, it is a no-op.
refresh_trust() {
  [ "$(effective_protocol)" = https ] || return 0
  if [ "$(id -u)" = 0 ]; then
    (cmd_trust --quiet) || say "warning: could not trust the emulator's certificate; run: cosmos-emulator trust"
  else
    "$0" trust --quiet || say "warning: could not trust the emulator's certificate; run: cosmos-emulator trust"
  fi
}

# One attempt at bringing the emulator up. Returns 0 ready, 1 not ready in
# time, 2 a failure another attempt may clear (dockerd restarted under it, for
# instance), 3 one it cannot; sets $outcome to the line for the state file.
boot_once() {
  say "boot: waiting for the Docker daemon"
  if ! wait_docker 120; then
    outcome="failed: the Docker daemon did not answer within 120s"
    return 2
  fi
  if ! resolve_config; then
    outcome="failed: invalid kit args"
    return 3
  fi
  say "boot: $image over $protocol"
  if ! ensure; then
    outcome="failed: could not start the emulator container"
    return 2
  fi
  say "boot: waiting for the emulator's readiness probe"
  wait_ready 600
  case $? in
    0)
      outcome=ready
      return 0
      ;;
    1)
      outcome="not-ready: no readiness after 600s"
      return 1
      ;;
    2)
      outcome="failed: the emulator container exited"
      return 2
      ;;
    *)
      outcome="failed: the emulator container disappeared"
      return 2
      ;;
  esac
}

cmd_boot() {
  stamp=1
  set_state starting
  attempt=1
  while :; do
    boot_once
    rc=$?
    if [ "$rc" -ne 2 ] || [ "$attempt" -ge 3 ]; then
      break
    fi
    say "boot: ${outcome#failed: }; trying again"
    attempt=$((attempt + 1))
    sleep 5
  done
  set_state "$outcome"
  case $rc in
    0)
      say "boot: ready at $(endpoint)"
      refresh_trust
      ;;
    1) say "boot: not ready after 600s; the container keeps running (cosmos-emulator logs)" ;;
    *)
      say "boot: ${outcome#failed: }"
      if exists; then
        say "boot: the emulator's last lines:"
        docker logs --tail 30 "$CONTAINER" >&2 2>&1
      fi
      ;;
  esac
  exit 0
}

wait_failed() {
  say "not ready: $1"
  b=$(boot_state)
  [ -z "$b" ] || say "boot hook: $b"
  if ! docker_up; then
    say "docker: $(docker info 2>&1 >/dev/null | tail -n 1)"
  else
    s=$(state)
    say "container: ${s:-absent}"
  fi
  if [ -r "$BOOT_LOG" ]; then
    say "last lines of $BOOT_LOG:"
    tail -n 15 "$BOOT_LOG" >&2
  fi
  say "more: cosmos-emulator logs; to retry: cosmos-emulator start"
  exit 1
}

# Passive: waits for whatever the boot hook (or `start`) is doing, and stops
# early only on an outcome that cannot turn into ready by itself.
cmd_wait() {
  secs=${1:-600}
  is_count "$secs" || die "wait takes a number of seconds, not '$secs'"
  deadline=$(($(date +%s) + secs))
  while :; do
    if ready; then
      say "ready at $(endpoint)"
      return 0
    fi
    # While the boot hook is still at work, every container state can pass: it
    # may be pulling, or about to start a container it found stopped. An empty
    # state from an unreachable daemon is not a missing container either.
    b=$(boot_state)
    if [ "$b" != starting ]; then
      s=$(state)
      case $s:$b in
        exited:* | dead:*) wait_failed "the emulator container has $s" ;;
        :failed* | created:failed*) wait_failed "the boot hook failed" ;;
        :ready | :not-ready*) docker_up && wait_failed "there is no emulator container" ;;
      esac
    fi
    [ "$(date +%s)" -lt "$deadline" ] || wait_failed "nothing answered within ${secs}s"
    sleep 2
  done
}

cmd_status() {
  need_docker
  resolve_config || exit 1
  b=$(boot_state)
  if ! exists; then
    printf 'container:  absent\n'
    printf 'boot:       %s\n' "${b:-not run}"
    return 1
  fi
  ep=$(effective_protocol)
  digest=$(docker image inspect -f '{{join .RepoDigests ", "}}' "$(container_image_id)" 2>/dev/null)
  printf 'container:  %s (%s)\n' "$CONTAINER" "$(state)"
  printf 'image:      %s\n' "$(container_image)"
  printf 'digest:     %s\n' "${digest:-unknown}"
  printf 'protocol:   %s\n' "$ep"
  printf 'endpoint:   %s://localhost:%s/\n' "$ep" "$GATEWAY_PORT"
  xp=$(container_env EXPLORER_PROTOCOL)
  printf 'explorer:   %s://localhost:%s/\n' "${xp:-$ep}" "$EXPLORER_PORT"
  if [ "$ep" = https ]; then
    if [ "$(container_env CERT_PATH)" != "$CERT_MOUNT/emulator.pfx" ]; then
      printf "cert:       the image's built-in one, not trusted\n"
    else
      expiry=$(docker exec "$CONTAINER" openssl x509 -enddate -noout -in "$CERT_MOUNT/tls.crt" 2>/dev/null)
      printf "cert:       this sandbox's own, in docker volume %s%s\n" "$CERT_VOLUME" "${expiry:+; expires ${expiry#notAfter=}}"
    fi
  fi
  printf 'data:       docker volume %s\n' "$VOLUME"
  printf 'boot:       %s\n' "${b:-not run}"
  rc=0
  if ready; then
    printf 'ready:      yes\n'
  else
    printf 'ready:      no\n'
    rc=1
  fi
  if detail=$(health_get status); then
    printf 'health:     %s\n' "$(printf '%s' "$detail" | tr -s '\n' ' ')"
  fi
  if drifted; then
    printf 'note:       out of date, as %s; cosmos-emulator restart recreates it\n' "$drift"
  fi
  return "$rc"
}

cmd_env() {
  resolve_config || exit 1
  ep=$(effective_protocol)
  url="$ep://localhost:$GATEWAY_PORT/"
  np=${NO_PROXY:-${no_proxy:-}}
  for host in localhost 127.0.0.1; do
    case ",$np," in
      *",$host,"*) ;;
      *) np="${np:+$np,}$host" ;;
    esac
  done
  printf 'export COSMOS_EMULATOR_PROTOCOL=%s\n' "$(quote "$ep")"
  printf 'export COSMOS_EMULATOR_ENDPOINT=%s\n' "$(quote "$url")"
  printf 'export COSMOS_EMULATOR_KEY=%s\n' "$(quote "$key")"
  printf 'export COSMOS_EMULATOR_CONNECTION_STRING=%s\n' "$(quote "AccountEndpoint=$url;AccountKey=$key;")"
  printf 'export NO_PROXY=%s\n' "$(quote "$np")"
  printf 'export no_proxy=%s\n' "$(quote "$np")"
}

cmd_logs() {
  n=${1:-100}
  is_count "$n" || die "logs takes a number of lines, not '$n'"
  if [ -r "$BOOT_LOG" ]; then
    printf '==> %s <==\n' "$BOOT_LOG"
    tail -n "$n" "$BOOT_LOG"
  fi
  if exists; then
    printf '\n==> docker logs %s <==\n' "$CONTAINER"
    docker logs --tail "$n" "$CONTAINER" 2>&1
  fi
}

cmd_start() {
  need_docker
  resolve_config || exit 1
  start_resolved "$@"
}

# Resolving again here would lose settings that came from a container that
# `reset` has just removed.
start_resolved() {
  ensure || die "could not start the emulator container"
  cmd_wait "${1:-600}"
  refresh_trust
}

cmd_stop() {
  need_docker
  if ! exists; then
    say "there is no emulator container"
    return 0
  fi
  docker stop "$CONTAINER" >/dev/null || die "could not stop the emulator container"
  say "stopped; the data stays in volume $VOLUME, and the next sandbox start runs it again"
}

cmd_restart() {
  need_docker
  resolve_config || exit 1
  if exists && ! drifted; then
    docker restart "$CONTAINER" >/dev/null || die "could not restart the emulator container"
  fi
  start_resolved "$@"
}

cmd_reset() {
  [ "${1:-}" = --yes ] ||
    die "reset deletes every database in the emulator (docker volume $VOLUME); run: cosmos-emulator reset --yes"
  shift
  need_docker
  resolve_config || exit 1
  docker rm --force "$CONTAINER" >/dev/null 2>&1
  if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    docker volume rm "$VOLUME" >/dev/null || die "could not remove volume $VOLUME"
  fi
  start_resolved "$@"
}

# cosmoshell.sh defaults to an http endpoint, so it is handed the connection
# string for the protocol the container actually serves.
cmd_shell() {
  need_docker
  running || die "the emulator is not running; start it with: cosmos-emulator start"
  cs="AccountEndpoint=$(endpoint);AccountKey=$key;"
  if [ -t 0 ] && [ -t 1 ]; then
    exec docker exec -it --env "COSMOS_CONNECTION_STRING=$cs" "$CONTAINER" cosmoshell.sh "$@"
  fi
  exec docker exec -i --env "COSMOS_CONNECTION_STRING=$cs" "$CONTAINER" cosmoshell.sh "$@"
}

# The certificate in the emulator's certificate volume, which is the one it
# serves once it was created with it.
own_cert() {
  docker exec "$CONTAINER" cat "$CERT_MOUNT/tls.crt" 2>/dev/null |
    awk '/-BEGIN CERTIFICATE-/ { p = 1 } p { print } p && /-END CERTIFICATE-/ { exit }'
}

trust_java() {
  kt=${COSMOS_EMULATOR_KEYTOOL:-}
  [ -n "$kt" ] || kt=$(command -v keytool 2>/dev/null) || return 0
  # keytool ends the base64 lines with CRLF.
  if "$kt" -list -rfc -cacerts -storepass changeit -alias cosmos-db-emulator 2>/dev/null | tr -d '\r' |
    awk '/-BEGIN CERTIFICATE-/ { p = 1 } p { print } p && /-END CERTIFICATE-/ { exit }' |
    cmp -s - "$TRUSTED_CERT"; then
    [ "$quiet" = --quiet ] || say "the Java cacerts store already has it ($kt)"
    return 0
  fi
  "$kt" -delete -cacerts -storepass changeit -alias cosmos-db-emulator >/dev/null 2>&1
  if "$kt" -importcert -noprompt -cacerts -storepass changeit -alias cosmos-db-emulator -file "$TRUSTED_CERT" >/dev/null 2>&1; then
    say "added it to the Java cacerts store ($kt)"
  else
    say "warning: could not add it to the Java cacerts store; by hand: keytool -importcert -cacerts -alias cosmos-db-emulator -file $TRUSTED_CERT"
  fi
}

# Trusts only this sandbox's own certificate. The image's built-in one is never
# trusted: its private key, and that of the CA that signed it, are public.
cmd_trust() {
  quiet=${1:-}
  if [ "$(id -u)" != 0 ]; then
    if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
      die "trust writes the system trust store, so it needs root or passwordless sudo"
    fi
    # sudo resets PATH, so a JDK found through the login shell's PATH is passed on.
    exec sudo -n env "COSMOS_EMULATOR_KEYTOOL=$(command -v keytool 2>/dev/null || true)" "$0" trust "$quiet"
  fi
  need_docker
  running || die "the emulator is not running; start it with: cosmos-emulator start"
  [ "$(effective_protocol)" = https ] || die "the emulator serves http; trust is for protocol=https"
  [ "$(container_env CERT_PATH)" = "$CERT_MOUNT/emulator.pfx" ] ||
    die "the emulator serves the image's built-in certificate, which is not trusted; cosmos-emulator restart moves it to this sandbox's own"
  pem=$(own_cert)
  [ -n "$pem" ] || die "could not read the certificate from volume $CERT_VOLUME"
  command -v update-ca-certificates >/dev/null 2>&1 ||
    die "update-ca-certificates not found; install the ca-certificates package"
  mkdir -p "${TRUSTED_CERT%/*}" || exit 1
  printf '%s\n' "$pem" >"$TRUSTED_CERT.new" || exit 1
  if cmp -s "$TRUSTED_CERT.new" "$TRUSTED_CERT"; then
    rm -f "$TRUSTED_CERT.new"
    [ "$quiet" = --quiet ] || say "the system trust store already has this certificate ($TRUSTED_CERT)"
  else
    mv -f "$TRUSTED_CERT.new" "$TRUSTED_CERT" || exit 1
    update-ca-certificates >/dev/null || die "update-ca-certificates failed"
    say "added the emulator's certificate to the system trust store ($TRUSTED_CERT)"
  fi
  trust_java
  if [ "$quiet" != --quiet ]; then
    say "Node.js reads its own store: export NODE_EXTRA_CA_CERTS=$TRUSTED_CERT"
    say "Python requests reads its own store: export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt"
    say "the certificate is this sandbox's own, kept in docker volume $CERT_VOLUME and renewed 30 days before it expires; each start this helper drives trusts it again"
  fi
}

usage() {
  cat <<'EOF'
Usage: cosmos-emulator <command> [args]

Runs the Azure Cosmos DB emulator (vNext, API for NoSQL) on this sandbox's
Docker Engine: the gateway on port 8081, Data Explorer on port 1234.

  wait [SECONDS]     Block until the emulator is ready (default 600)
  status             Container, image, endpoint and readiness; exit 0 when ready
  env                Print export lines for the endpoint, key and connection
                     string: eval "$(cosmos-emulator env)"
  logs [LINES]       The boot log and the emulator's own log (default 100)
  start [SECONDS]    Create or start the emulator, then wait for it
  stop               Stop the emulator; the data stays, and the next sandbox
                     start runs it again
  restart [SECONDS]  Restart the emulator, recreating it if the settings changed
  reset --yes        Delete the emulator and all of its data, then start afresh
  shell [ARGS]       Open the Cosmos DB shell (cosmoshell) inside the emulator
  trust              Add the emulator's https certificate, which is this
                     sandbox's own, to the system and Java trust stores
                     (protocol=https only)
  boot               What the kit's startup hook runs

Settings come from COSMOS_EMULATOR_PROTOCOL (http or https) and
COSMOS_EMULATOR_IMAGE_TAG (a vnext-* tag), which the kit's args set.
EOF
}

cmd=${1:-help}
[ "$#" -eq 0 ] || shift
case $cmd in
  boot) cmd_boot ;;
  wait) cmd_wait "$@" ;;
  status) cmd_status ;;
  env) cmd_env ;;
  logs) cmd_logs "$@" ;;
  start) cmd_start "$@" ;;
  stop) cmd_stop ;;
  restart) cmd_restart "$@" ;;
  reset) cmd_reset "$@" ;;
  shell) cmd_shell "$@" ;;
  trust) cmd_trust "$@" ;;
  help | -h | --help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac
