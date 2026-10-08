# redis-agent

Mixin kit that adds a local Redis instance to any sandbox agent. Redis runs
inside the sandbox via Docker-in-Docker and is ready on localhost:6379. Includes
redis-py in an isolated Python venv with a cache.py helper covering the patterns
AI agents use most: key-value caching, pub/sub messaging, and task queues.

## Usage

    sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=redis-agent" claude

Swap claude for any other agent — pi, hermes-agent, or your own custom agent.

## Prerequisites

No external accounts or credentials required. Redis runs entirely inside the sandbox.

## How it works

### Redis inside the sandbox

The startup command pulls redis:7-alpine from Docker Hub and runs it inside the
sandbox's private Docker daemon (the shell-docker template ships with
Docker-in-Docker). Redis listens on localhost:6379 with no authentication.

Because Redis runs inside the microVM, sbx rm deletes everything including all
stored data. Redis does not persist to disk by default — a sandbox restart clears
all keys.

### Python environment

redis-py (with the hiredis C extension for performance) is installed into an
isolated venv at /opt/redis-agent. The venv is prepended to PATH via
/etc/sandbox-persistent.sh, which is sourced in every shell context including
non-interactive agent tool calls (via BASH_ENV).

## What is inside the sandbox

    /home/agent/workspace/
    cache.py    # redis-py helper — set/get, enqueue/dequeue, publish/subscribe
    REDIS.md    # Loaded by the agent on startup

### cache.py

Key-value cache with optional TTL:

    from cache import set, get, delete

    set("result:run-42", {"status": "done", "tokens": 1024}, ttl=3600)
    value = get("result:run-42")   # returns the dict, not a JSON string
    delete("result:run-42")

Task queue (blocking producer/consumer):

    from cache import enqueue, dequeue

    # Producer agent
    enqueue("tasks", {"type": "summarize", "doc_id": "abc123"})

    # Consumer agent — blocks until a task arrives
    task = dequeue("tasks", timeout=30)

Pub/sub (event-driven agents):

    from cache import publish, subscribe

    # Publisher
    publish("agent-events", {"event": "analysis_complete", "id": "run-42"})

    # Subscriber
    ps = subscribe("agent-events")
    for msg in ps.listen():
        print(msg["data"])

Raw redis-py client for advanced use:

    from cache import client
    r = client()
    r.incr("counter")
    r.expire("my-key", 60)

## Network policy

The sandbox runs under a deny-all baseline. Only these domains are reachable:

    registry-1.docker.io, auth.docker.io                    -- Docker Hub (Redis image)
    production.cloudflare.docker.com, index.docker.io       -- Docker Hub CDN and index
    pypi.org, files.pythonhosted.org, pythonhosted.org      -- pip installs
    archive.ubuntu.com, security.ubuntu.com, ports.ubuntu.com -- apt (amd64 + arm64)
    download.docker.com                                     -- Docker apt repo

## Using an external Redis instance

Set REDIS_URL before creating the sandbox and cache.py will connect to your
external instance instead of the local one:

    export REDIS_URL=redis://your-host:6379
