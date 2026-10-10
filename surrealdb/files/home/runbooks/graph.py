#!/usr/bin/env python3
"""A tiny multi-model demo: documents + graph edges in one embedded SurrealDB.

Ships with the sbx-kits-surrealdb kit. This one needs no embedder and no cloud
keys - it shows the part of SurrealDB a pure vector store can't do: typed records
linked by graph edges (`RELATE a->edge->b`) and traversed inline in a query
(`->visited->city`).

Usage (inside the sandbox):
    python3 ~/runbooks/graph.py
"""
import json

from surrealdb import Surreal

with open("/home/agent/.surrealdb/config.json") as f:
    cfg = json.load(f)

db = Surreal(cfg["db"]["url"])
db.connect()
try:
    db.signin({"username": "root", "password": "root"})
except Exception:
    pass  # embedded engines don't authenticate
db.use(cfg["db"]["namespace"], "graph_demo")

# Wipe demo tables first so re-running doesn't error on the fixed record IDs
# (CREATE fails if the record already exists); each run starts from a clean slate.
for t in ("person", "city", "visited"):
    db.query(f"REMOVE TABLE IF EXISTS {t};")

# Documents: people and cities as typed records.
db.query("CREATE person:alice SET name = 'Alice', home = 'Berlin';")
db.query("CREATE person:bob   SET name = 'Bob',   home = 'Lisbon';")
db.query("CREATE city:lisbon  SET name = 'Lisbon', country = 'Portugal';")
db.query("CREATE city:porto   SET name = 'Porto',  country = 'Portugal';")
db.query("CREATE city:berlin  SET name = 'Berlin', country = 'Germany';")

# Graph: who visited where, with a property on the edge itself.
db.query("RELATE person:alice->visited->city:lisbon SET year = 2024, rating = 5;")
db.query("RELATE person:alice->visited->city:porto  SET year = 2025, rating = 4;")
db.query("RELATE person:bob->visited->city:berlin   SET year = 2025, rating = 5;")

# Traverse the graph inline: cities Alice has visited.
alice = db.query("SELECT name, ->visited->city.name AS visited FROM person:alice;")
print("Alice visited:", alice)

# Traverse the other direction: who has visited Lisbon.
lisbon = db.query("SELECT name, <-visited<-person.name AS visitors FROM city:lisbon;")
print("Lisbon visitors:", lisbon)

# Edge properties are queryable too: trips rated 5.
top = db.query("SELECT in.name AS who, out.name AS city, year FROM visited WHERE rating = 5;")
print("5-star trips:", top)

db.close()
