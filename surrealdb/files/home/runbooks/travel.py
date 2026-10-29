#!/usr/bin/env python3
"""A tiny travel assistant that remembers the traveler across runs.

Ships with the sbx-kits-surrealdb kit. Memory is stored in an embedded SurrealDB
(on-disk surrealkv, no server) and retrieved with SurrealDB's *native* vector
search - text is embedded with the local Docker Model Runner, the vector is
stored next to the text, and recall is a KNN query over an HNSW index. The chat
reply also runs on the local Docker Model Runner, so it needs no cloud keys.

Usage (inside the sandbox):
    python3 ~/runbooks/travel.py "I'm vegetarian, I like aisle seats. Book me to Lisbon."
    python3 ~/runbooks/travel.py "Plan my return leg."     # a fresh process; it still knows you
"""
import os
import sys
import json

# sbx leaves an IPv6 "[::1]" entry in NO_PROXY that breaks the HTTP client's
# proxy-bypass matching, so calls to host.docker.internal get routed through the
# sandbox egress proxy and dropped. Strip it before any client is created.
for var in ("NO_PROXY", "no_proxy"):
    if var in os.environ:
        os.environ[var] = ",".join(e for e in os.environ[var].split(",") if e.strip() != "[::1]")

CONFIG = "/home/agent/.surrealdb/config.json"
USER = "traveler_123"
TABLE = "travel_memories"

with open(CONFIG) as f:
    cfg = json.load(f)

DIMS = cfg["embedder"]["dims"]


def embed(text):
    """Return an embedding vector for `text` using the kit's configured embedder."""
    e = cfg["embedder"]
    if e["provider"] == "gemini":
        from google import genai
        client = genai.Client()  # GOOGLE_API_KEY comes from the sandbox env / sbx proxy
        r = client.models.embed_content(
            model=e["model"],
            contents=text,
            config={"output_dimensionality": e["dims"]},
        )
        return list(r.embeddings[0].values)
    # openai-compatible: local Docker Model Runner or OpenAI
    from openai import OpenAI
    # For DMR the sbx proxy can inject an openrouter sentinel over OPENAI_API_KEY;
    # pin the local key so the embed call stays on the DMR endpoint.
    api_key = e.get("api_key") or os.environ.get("OPENAI_API_KEY") or "dmr"
    client = OpenAI(base_url=e.get("base_url"), api_key=api_key)
    return client.embeddings.create(model=e["model"], input=text).data[0].embedding


def connect():
    from surrealdb import Surreal
    db = Surreal(cfg["db"]["url"])
    db.connect()
    try:
        db.signin({"username": "root", "password": "root"})
    except Exception:
        pass  # embedded engines don't authenticate
    db.use(cfg["db"]["namespace"], cfg["db"]["database"])
    # Idempotent schema: a document table + an HNSW vector index over the embedding.
    db.query(f"DEFINE TABLE IF NOT EXISTS {TABLE} SCHEMALESS;")
    db.query(
        f"DEFINE INDEX IF NOT EXISTS {TABLE}_vec ON {TABLE} "
        f"FIELDS embedding HNSW DIMENSION {DIMS} DIST COSINE TYPE F32;"
    )
    return db


def remember(db, text):
    db.query(
        f"CREATE {TABLE} SET text = $t, embedding = $e, user_id = $u",
        {"t": text, "e": embed(text), "u": USER},
    )


def recall(db, query, k=5):
    rows = db.query(
        f"SELECT text, vector::distance::knn() AS dist FROM {TABLE} "
        f"WHERE user_id = $u AND embedding <|{k},64|> $vec ORDER BY dist ASC",
        {"u": USER, "vec": embed(query)},
    )
    return [r["text"] for r in (rows or [])]


def reply(db, question):
    profile = recall(db, question)
    print("recalled:", profile or "(nothing yet)")

    from openai import OpenAI
    chat = OpenAI(
        base_url=os.environ.get("OPENAI_BASE_URL", "http://host.docker.internal:12434/engines/v1"),
        api_key=os.environ.get("OPENAI_API_KEY", "dmr"),
    )
    prompt = (
        "You are a travel assistant.\n"
        f"What you already know about this traveler: {', '.join(profile) or 'nothing yet'}\n\n"
        f"Traveler: {question}"
    )
    answer = chat.chat.completions.create(
        model=os.environ.get("SURREAL_CHAT_MODEL", "ai/gemma3"),
        messages=[{"role": "user", "content": prompt}],
    ).choices[0].message.content

    remember(db, question)  # store it for next time
    return answer


if __name__ == "__main__":
    question = " ".join(sys.argv[1:]) or "Plan me a trip somewhere warm."
    db = connect()
    print(reply(db, question))
    db.close()
