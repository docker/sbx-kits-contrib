# Runbooks

Runnable demos shipped with the SurrealDB kit. They live at `~/runbooks/` in the
sandbox and use the embedded SurrealDB at `~/.surrealdb/data` (config at
`~/.surrealdb/config.json`).

## travel.py

A travel assistant that remembers the traveler across separate runs. Memory is
stored in SurrealDB and retrieved with its native vector search (an HNSW index +
KNN query); text is embedded, and on the default kit both the embedder and the
chat model are the local Docker Model Runner, so no cloud keys are needed.

```console
python3 ~/runbooks/travel.py "I'm vegetarian, I like aisle seats. Book me to Lisbon."
python3 ~/runbooks/travel.py "Plan my return leg."   # fresh process; it still knows you
```

The first run starts with an empty profile; the second recalls what you told it
by embedding the new question and running a KNN search over the stored vectors.

## graph.py

A multi-model demo - no embedder, no keys. It builds a tiny travel knowledge
graph (people and cities as documents, `visited` as graph edges) and traverses it
inline in queries. This is the part of SurrealDB a plain vector store can't do.

```console
python3 ~/runbooks/graph.py
```
