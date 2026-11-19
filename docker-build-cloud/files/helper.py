#!/usr/bin/env python3
"""Helper for the docker-build-cloud kit. Standard library only.

  setup      write the placeholder Docker login, then create the Build Cloud
             builder (or select it, if it exists) against the shim
  serve      a loopback HTTP shim for the one Docker Hub request that the
             sandbox proxy cannot authenticate
  self-test  exercise all of it, with no network; the kit's build runs this

Why a shim at all. To resolve a Build Cloud builder, buildx first POSTs the
Docker login to https://hub.docker.com/v2/auth/token as JSON, with the
credential in the request *body*, and uses the answer as a Bearer token for the
builder lookup that follows. The sandbox proxy injects headers, not bodies, so
Hub would see the kit's placeholder and answer 401. The lookup itself accepts
the header the proxy injects, so the token from the first call is never needed.

buildx is pointed at this shim with the driver option `internal.hub.host`. The
shim answers the token request with a dummy, and forwards the builder lookup to
Docker Hub without any Authorization header, which is where the proxy adds the
real one. Nothing secret passes through it, and it keeps none.
"""
import argparse
import base64
import http.client
import http.server
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

HUB = "https://hub.docker.com"
DEFAULT_PORT = 8099
DEFAULT_ENTRY = "https://index.docker.io/v1/"
MIN_BUILDX = (0, 37, 0)
# The same shape the descriptor's `builder` arg enforces.
BUILDER_RE = re.compile(r"[a-z0-9][a-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_-]*")

TOKEN_PATH = "/v2/auth/token"
BUILDS_PREFIX = "/v2/cloud-builds/"
HEALTH_PATH = "/healthz"
HEALTH_BODY = b"docker-build-cloud shim\n"
DUMMY_TOKEN = "docker-build-cloud-shim"

UPSTREAM_TIMEOUT = 20
MAX_BODY = 1 << 20
MAX_PATH = 512


def builds_path_ok(path):
    """True for a Cloud Builds API path that is safe to forward to Hub.

    The prefix is checked on the raw path, which is what gets forwarded. The
    decoded form is checked as well, so an encoded `..` or `/` cannot climb out
    of the prefix on Hub's side.
    """
    if len(path) > MAX_PATH or not path.startswith(BUILDS_PREFIX):
        return False
    decoded = urllib.parse.unquote(path)
    if "\\" in decoded or "//" in decoded or any(ord(c) < 32 for c in decoded):
        return False
    return not {".", ".."} & set(decoded.split("/"))


def make_handler(upstream, opener):
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "docker-build-cloud-shim"
        protocol_version = "HTTP/1.0"

        def _reply(self, status, body, ctype="application/json"):
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _error(self, status, message):
            self._reply(status, json.dumps({"message": message}).encode())

        def do_GET(self):
            path, _, query = self.path.partition("?")
            if path == HEALTH_PATH:
                return self._reply(200, HEALTH_BODY, "text/plain")
            if not builds_path_ok(path):
                return self._error(404, "not served by the docker-build-cloud shim")
            # No Authorization header and nothing else from the caller is
            # forwarded: the proxy adds the real credential on the way out.
            url = upstream + path + ("?" + query if query else "")
            request = urllib.request.Request(
                url,
                headers={"Accept": "application/json", "User-Agent": "docker-build-cloud-shim"},
            )
            try:
                with opener.open(request, timeout=UPSTREAM_TIMEOUT) as resp:
                    status, headers, body = resp.status, resp.headers, resp.read(MAX_BODY + 1)
            except urllib.error.HTTPError as err:
                status, headers, body = err.code, err.headers, err.read(MAX_BODY + 1)
            except (urllib.error.URLError, OSError) as err:
                return self._error(502, "could not reach %s: %s" % (upstream, err))
            if len(body) > MAX_BODY:
                return self._error(502, "response from %s is too large" % upstream)
            self._reply(status, body, headers.get("Content-Type", "application/json"))

        def do_POST(self):
            if self.path.partition("?")[0] != TOKEN_PATH:
                return self._error(404, "not served by the docker-build-cloud shim")
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            # The body holds the placeholder login. It is read to finish the
            # request and dropped.
            self.rfile.read(max(0, min(length, MAX_BODY)))
            self._reply(200, json.dumps({"access_token": DUMMY_TOKEN}).encode())

        def _not_allowed(self):
            self._error(405, "method not allowed")

        do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = _not_allowed

        def log_message(self, fmt, *args):
            # Method, path and status only: never headers or bodies.
            sys.stderr.write("shim: %s\n" % (fmt % args))

    return Handler


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True


def shim_answers(port):
    try:
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        conn.request("GET", HEALTH_PATH)
        return conn.getresponse().read() == HEALTH_BODY
    except OSError:
        return False


def cmd_serve(args):
    handler = make_handler(HUB, urllib.request.build_opener())
    try:
        server = Server(("127.0.0.1", args.port), handler)
    except OSError as err:
        # A shim from an earlier run of the hook is fine to leave in place.
        if shim_answers(args.port):
            print("shim already running on 127.0.0.1:%d" % args.port, flush=True)
            return 0
        print("cannot listen on 127.0.0.1:%d: %s" % (args.port, err), file=sys.stderr)
        return 1
    print("shim listening on 127.0.0.1:%d" % args.port, flush=True)
    server.serve_forever()
    return 0


def merge_login(config_path, entry, username, password):
    """Set auths[entry].auth in a Docker config, keeping everything else.

    Returns True if the file changed. A file that is not a JSON object is an
    error and is left alone.
    """
    cfg = {}
    if os.path.exists(config_path) and os.path.getsize(config_path) > 0:
        try:
            with open(config_path) as f:
                cfg = json.load(f)
        except json.JSONDecodeError as err:
            raise SystemExit("%s is not valid JSON, leaving it alone: %s" % (config_path, err))
    if not isinstance(cfg, dict) or not isinstance(cfg.get("auths", {}), dict):
        raise SystemExit("%s does not have the shape of a Docker config, leaving it alone" % config_path)

    auth = base64.b64encode(("%s:%s" % (username, password)).encode()).decode()
    auths = cfg.setdefault("auths", {})
    current = auths.get(entry)
    if isinstance(current, dict) and current.get("auth") == auth:
        return False
    auths[entry] = dict(current, auth=auth) if isinstance(current, dict) else {"auth": auth}

    directory = os.path.dirname(config_path) or "."
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".config.json.")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, config_path)
    except BaseException:
        os.unlink(tmp)
        raise
    return True


def buildx_version():
    """The installed buildx as a tuple, or None if there is no buildx."""
    try:
        result = subprocess.run(["docker", "buildx", "version"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    fields = result.stdout.split()
    match = re.match(r"v?(\d+)\.(\d+)\.(\d+)", fields[1]) if result.returncode == 0 and len(fields) > 1 else None
    return tuple(int(n) for n in match.groups()) if match else None


def wait_for_shim(port, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if shim_answers(port):
            return True
        time.sleep(0.25)
    return shim_answers(port)


def fail(message):
    print("docker-build-cloud: %s" % message, file=sys.stderr, flush=True)
    return 1


def cmd_setup(args):
    """Make the Build Cloud builder the default buildx builder.

    With --serve, the shim runs inside this process for the duration: that is
    how the install hook works, before the boot-time shim exists. Without it,
    the shim is expected to be running already, as it is at boot.
    """
    if not BUILDER_RE.fullmatch(args.builder):
        return fail("builder %r is not ORG/NAME" % args.builder)
    endpoint = "cloud-" + args.builder.replace("/", "-")

    version = buildx_version()
    if version is None:
        return fail("the Docker CLI has no buildx plugin in this sandbox")
    if version < MIN_BUILDX:
        return fail("buildx %s is too old; the cloud driver needs %s or later" % (
            ".".join(map(str, version)), ".".join(map(str, MIN_BUILDX))))

    # buildx refuses to resolve a builder with no entry for index.docker.io
    # ("no credentials found"). The proxy swaps the real token in on the
    # requests it can, and the shim covers the one it cannot. Merged into any
    # config already there.
    password = os.environ.get("DOCKER_ACCESS_TOKEN") or "proxy-managed"
    changed = merge_login(os.path.join(args.home, ".docker", "config.json"), DEFAULT_ENTRY, "sbx-login", password)
    print("docker config %s" % ("updated" if changed else "already current"), flush=True)

    server = None
    if args.serve:
        try:
            server = Server(("127.0.0.1", args.port), make_handler(HUB, urllib.request.build_opener()))
            threading.Thread(target=server.serve_forever, daemon=True).start()
        except OSError:
            server = None  # the port is taken: an earlier shim, checked next
    try:
        if not wait_for_shim(args.port, args.shim_timeout):
            return fail("the Docker Hub shim is not answering on 127.0.0.1:%d; see /tmp/docker-build-cloud-shim.log" % args.port)

        # `buildx create` refuses a name it already has, and this runs again on
        # every boot, so select the existing instance instead. `create` calls
        # Hub to resolve the builder, through the shim, so it fails on a
        # builder the account cannot use, on an expired login, or on the
        # network. buildx's own error is printed before the message below.
        instance = os.path.join(args.home, ".docker", "buildx", "instances", endpoint)
        if os.path.exists(instance):
            return subprocess.run(["docker", "buildx", "use", endpoint]).returncode
        result = subprocess.run(
            ["docker", "buildx", "create", "--driver", "cloud", "--use",
             "--driver-opt", "internal.hub.host=http://127.0.0.1:%d" % args.port, args.builder],
            capture_output=True, text=True)
        output = result.stdout + result.stderr
        if result.returncode == 0:
            print(output, end="", flush=True)
            return 0
        print(output, end="" if output.endswith("\n") else "\n", file=sys.stderr, flush=True)
        if "existing instance" in output:
            return subprocess.run(["docker", "buildx", "use", endpoint]).returncode
        return fail("could not create the %s Build Cloud builder, so builds would run on the local engine. "
                    "Check the builder name, that sbx is logged in on the host, and that the account can use the builder."
                    % args.builder)
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()


STUB_DOCKER = """#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
  "buildx version") echo "github.com/docker/buildx ${STUB_BUILDX:-v0.38.1} abc" ;;
  "buildx create")
    if [ -n "${STUB_FAIL:-}" ]; then echo "$STUB_FAIL" >&2; exit 1; fi
    mkdir -p "$STUB_HOME/.docker/buildx/instances"
    : > "$STUB_HOME/.docker/buildx/instances/cloud-org-name" ;;
esac
"""


def test_setup(check):
    """Run `setup` against a stub docker, covering each way it can end."""
    import argparse
    import contextlib
    import io

    def free_port():
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            return s.getsockname()[1]

    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        os.makedirs(home)
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        stub = os.path.join(bindir, "docker")
        with open(stub, "w") as f:
            f.write(STUB_DOCKER)
        os.chmod(stub, 0o755)
        log = os.path.join(tmp, "calls")
        open(log, "w").close()

        saved = {k: os.environ.get(k) for k in ("PATH", "STUB_LOG", "STUB_HOME", "STUB_BUILDX", "STUB_FAIL")}
        os.environ.update(PATH=bindir + os.pathsep + os.environ.get("PATH", ""), STUB_LOG=log, STUB_HOME=home)
        os.environ.pop("STUB_BUILDX", None)
        os.environ.pop("STUB_FAIL", None)

        def calls():
            with open(log) as f:
                return f.read().splitlines()

        def run(serve, port, builder="org/name"):
            args = argparse.Namespace(builder=builder, home=home, port=port, serve=serve, shim_timeout=1)
            err = io.StringIO()
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                rc = cmd_setup(args)
            return rc, err.getvalue()

        def reset():
            open(log, "w").close()
            shutil.rmtree(os.path.join(home, ".docker", "buildx"), ignore_errors=True)

        try:
            port = free_port()
            os.environ["STUB_BUILDX"] = "v0.36.0"
            rc, err = run(True, port)
            check("setup refuses old buildx", rc == 1 and "too old" in err, (rc, err))
            check("setup old buildx creates nothing", not any(" create" in c for c in calls()), calls())
            os.environ.pop("STUB_BUILDX")

            rc, err = run(True, port, builder="not-a-builder")
            check("setup refuses a bad builder name", rc == 1 and "ORG/NAME" in err, (rc, err))

            reset()
            rc, err = run(True, port)
            check("setup creates the builder", rc == 0, (rc, err))
            check("setup create arguments", ("buildx create --driver cloud --use --driver-opt "
                                             "internal.hub.host=http://127.0.0.1:%d org/name" % port) in calls(), calls())
            check("setup stops its own shim", not shim_answers(port))
            with open(os.path.join(home, ".docker", "config.json")) as f:
                check("setup writes the login", DEFAULT_ENTRY in json.load(f)["auths"])

            # At boot the shim is a separate process: stand one in for it.
            external = Server(("127.0.0.1", port), make_handler(HUB, urllib.request.build_opener(urllib.request.ProxyHandler({}))))
            threading.Thread(target=external.serve_forever, daemon=True).start()
            try:
                before = len([c for c in calls() if " create" in c])
                rc, err = run(False, port)
                check("setup selects an existing builder", rc == 0 and "buildx use cloud-org-name" in calls(), (rc, calls()))
                check("setup does not create it twice", len([c for c in calls() if " create" in c]) == before, calls())

                reset()
                os.environ["STUB_FAIL"] = "ERROR: unknown builder: no builders found for group: org/name"
                rc, err = run(False, port)
                check("setup fails when create fails", rc == 1 and "no builders found" in err
                      and "could not create the org/name" in err, (rc, err))

                os.environ["STUB_FAIL"] = "ERROR: existing instance for cloud-org-name but no append mode"
                reset()
                rc, err = run(False, port)
                check("setup recovers from an existing instance", rc == 0 and "buildx use cloud-org-name" in calls(), (rc, calls(), err))
                os.environ.pop("STUB_FAIL")
            finally:
                external.shutdown()
                external.server_close()

            rc, err = run(False, port)
            check("setup fails with no shim", rc == 1 and "shim is not answering" in err, (rc, err))
        finally:
            for k, v in saved.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


def cmd_self_test(_args):
    failures = []

    def check(name, ok, detail=""):
        if not ok:
            failures.append("%s %s" % (name, detail))

    seen = []

    class Upstream(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append((self.path, {k.lower(): v for k, v in self.headers.items()}))
            body = b'{"results": []}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *a):
            pass

    no_proxy = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    up = Server(("127.0.0.1", 0), Upstream)
    shim = Server(("127.0.0.1", 0), make_handler("http://127.0.0.1:%d" % up.server_address[1], no_proxy))
    dead = Server(("127.0.0.1", 0), make_handler("http://127.0.0.1:1", no_proxy))
    servers = (up, shim, dead)
    for s in servers:
        threading.Thread(target=s.serve_forever, daemon=True).start()

    def call(server, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", server.server_address[1], timeout=5)
        conn.request(method, path, body=body, headers=headers or {})
        resp = conn.getresponse()
        return resp.status, resp.read()

    try:
        status, body = call(shim, "GET", HEALTH_PATH)
        check("health", status == 200 and body == HEALTH_BODY, (status, body))

        status, body = call(
            shim, "POST", TOKEN_PATH,
            body=json.dumps({"identifier": "someone", "secret": "proxy-managed"}),
            headers={"Content-Type": "application/json", "Authorization": "Bearer x"},
        )
        check("token status", status == 200, status)
        check("token body", json.loads(body).get("access_token") == DUMMY_TOKEN, body)
        check("token is not forwarded", seen == [], seen)

        lookup = BUILDS_PREFIX + "accounts/org/builder-groups/name/instances"
        status, body = call(shim, "GET", lookup + "?page=1", headers={"Authorization": "Bearer placeholder"})
        check("lookup status", status == 200 and json.loads(body) == {"results": []}, (status, body))
        check("lookup path", [p for p, _ in seen] == [lookup + "?page=1"], seen)
        check("lookup drops Authorization", all("authorization" not in h for _, h in seen), seen)

        refused = len(seen)
        for method, path in (
            ("GET", TOKEN_PATH),
            ("GET", "/v2/users/someone"),
            ("GET", BUILDS_PREFIX + "../users/someone"),
            ("GET", BUILDS_PREFIX + "%2e%2e/users/someone"),
            ("GET", BUILDS_PREFIX + "a//b"),
            ("GET", BUILDS_PREFIX + "a%2f%2e%2e%2fb"),
            ("POST", BUILDS_PREFIX + "x"),
            ("POST", "/v2/other"),
        ):
            status, _ = call(shim, method, path)
            check("refuses %s %s" % (method, path), status == 404, status)
        status, _ = call(shim, "PUT", lookup)
        check("refuses PUT", status == 405, status)
        check("refused requests are not forwarded", len(seen) == refused, seen[refused:])

        status, body = call(dead, "GET", lookup)
        check("unreachable upstream", status == 502, (status, body))
    finally:
        for s in servers:
            s.shutdown()
            s.server_close()

    with tempfile.TemporaryDirectory() as tmp:
        cfg = os.path.join(tmp, ".docker", "config.json")
        check("login creates", merge_login(cfg, DEFAULT_ENTRY, "sbx-login", "proxy-managed") is True)
        check("login mode", os.stat(cfg).st_mode & 0o777 == 0o600, oct(os.stat(cfg).st_mode))
        with open(cfg) as f:
            first = f.read()
        check("login idempotent", merge_login(cfg, DEFAULT_ENTRY, "sbx-login", "proxy-managed") is False)
        with open(cfg) as f:
            check("login unchanged", f.read() == first)
        expect = base64.b64encode(b"sbx-login:proxy-managed").decode()
        check("login value", json.loads(first)["auths"][DEFAULT_ENTRY]["auth"] == expect, first)

        with open(cfg, "w") as f:
            json.dump({"credsStore": "x", "auths": {"other.example": {"auth": "eg"}}}, f)
        merge_login(cfg, DEFAULT_ENTRY, "sbx-login", "proxy-managed")
        with open(cfg) as f:
            merged = json.load(f)
        check("login keeps other keys", merged.get("credsStore") == "x" and "other.example" in merged["auths"], merged)

        with open(cfg, "w") as f:
            f.write("{not json")
        try:
            merge_login(cfg, DEFAULT_ENTRY, "sbx-login", "proxy-managed")
            check("login refuses invalid JSON", False)
        except SystemExit:
            with open(cfg) as f:
                check("login leaves invalid JSON alone", f.read() == "{not json")

    test_setup(check)

    if failures:
        for failure in failures:
            print("FAIL: %s" % failure, file=sys.stderr)
        return 1
    print("self-test passed")
    return 0


def main():
    parser = argparse.ArgumentParser(prog="helper.py", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    serve = sub.add_parser("serve", help="run the Docker Hub shim on loopback")
    serve.add_argument("--port", type=int, default=DEFAULT_PORT)
    serve.set_defaults(func=cmd_serve)

    setup = sub.add_parser("setup", help="create the Build Cloud builder, or select it")
    setup.add_argument("--builder", required=True, help="ORG/NAME")
    setup.add_argument("--home", required=True, help="the agent's home directory")
    setup.add_argument("--port", type=int, default=DEFAULT_PORT)
    setup.add_argument("--serve", action="store_true", help="run the shim inside this process while setting up")
    setup.add_argument("--shim-timeout", type=float, default=10, help="seconds to wait for the shim")
    setup.set_defaults(func=cmd_setup)

    test = sub.add_parser("self-test", help="run the built-in checks")
    test.set_defaults(func=cmd_self_test)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
