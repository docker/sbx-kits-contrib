# postgres-agent

Docker Sandbox Kit that runs PostgreSQL 16 with the pgvector extension inside the sandbox — no external database required. Includes the Anthropic SDK and psycopg3 for building AI agents that store structured data, JSON documents, and vector embeddings in a single SQL database.

## Usage

    sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=postgres-agent" postgres-agent

## Prerequisites

Set your Anthropic API key before creating the sandbox:

    sbx secret set anthropic

The key stays on your host. The sbx proxy injects it as an x-api-key header on outbound requests to api.anthropic.com. The sandbox never sees the real value.

## How it works

### PostgreSQL inside the sandbox

The startup command pulls pgvector/pgvector:pg16 from Docker Hub and runs it inside the sandbox's private Docker daemon (the shell-docker template ships with Docker-in-Docker). PostgreSQL listens on localhost:5432 with trust authentication. The vector extension is enabled automatically.

Because the database runs inside the microVM, sbx rm deletes everything including all data. Export anything you want to keep before removing the sandbox.

### Python environment

Python dependencies are installed into an isolated venv at /opt/postgres-agent. The python and python3 commands in the sandbox point to that venv.

### Credential injection

ANTHROPIC_API_KEY is set to a placeholder value inside the sandbox. The host-side proxy intercepts outbound requests to api.anthropic.com and substitutes the real key before forwarding. The agent can make authenticated API calls without ever reading the credential.

## What is inside the sandbox

    /home/agent/workspace/
    db.py       # psycopg3 connection helper — execute() and connection()
    AGENTS.md   # Loaded by the agent on startup

### db.py

    from db import execute, connection

    # Any SQL statement
    rows = execute("SELECT version()")

    # Parameterised query
    execute(
        "INSERT INTO events (data) VALUES (%s)",
        ('{"type": "run"}',)
    )

    # Raw connection for transactions
    with connection() as conn:
        ...

### pgvector

    # Create a table with a vector column
    execute("""
        CREATE TABLE documents (
            id BIGSERIAL PRIMARY KEY,
            content TEXT,
            embedding VECTOR(1536)
        )
    """)

    # HNSW index for cosine similarity
    execute("""
        CREATE INDEX ON documents
        USING hnsw (embedding vector_cosine_ops)
    """)

    # Insert
    execute(
        "INSERT INTO documents (content, embedding) VALUES (%s, %s)",
        ("some text", "[0.1, 0.2, ...]")
    )

    # Search
    rows = execute(
        "SELECT content FROM documents ORDER BY embedding <=> %s LIMIT 5",
        ("[0.1, 0.2, ...]",)
    )

Distance operators: <-> L2, <=> cosine, <#> inner product.

## Network policy

The sandbox runs under a deny-all baseline. Only these domains are reachable:

    api.anthropic.com, console.anthropic.com  — Claude API
    pypi.org, files.pythonhosted.org          — pip installs
    registry-1.docker.io, auth.docker.io      — Docker Hub (pgvector image)
    archive.ubuntu.com, security.ubuntu.com   — apt packages (amd64)
    ports.ubuntu.com                          — apt packages (arm64)
    download.docker.com                       — Docker apt repo

## Using an external PostgreSQL instance

Set these before creating the sandbox and db.py will connect to your external instance:

    export PGHOST=your-host
    export PGPORT=5432
    export PGUSER=your-user
    export PGDATABASE=your-db
