## Azure Cosmos DB emulator (API for NoSQL)

The Azure Cosmos DB emulator (vNext, Linux) runs as a container on this
sandbox's Docker Engine. A startup hook starts it in the background on every
sandbox start, and the `cosmos-emulator` command manages it.

- Before using it, block until it is ready: `cosmos-emulator wait`. The first
  start pulls a ~0.6 GB image, so allow a few minutes; later starts take
  seconds. A non-zero exit means it failed, and the output says why.
- Login shells already export the connection details. Anywhere else, such as a
  script or a non-login shell, run `eval "$(cosmos-emulator env)"`.
  - `COSMOS_EMULATOR_ENDPOINT`: `http://localhost:8081/`, or `https://` when
    the kit's `protocol` arg is `https`
  - `COSMOS_EMULATOR_KEY`: the emulator's published, well-known key. It is not
    a secret, and the emulator does not check it, but every SDK needs one.
  - `COSMOS_EMULATOR_CONNECTION_STRING`: both of the above as one string
- Read the endpoint and key from those variables rather than hard-coding them,
  so the same code can point at a real account later.
- Use gateway mode; direct mode is not available. `localhost` and `127.0.0.1`
  are in `NO_PROXY` so SDK traffic skips the sandbox's proxy. Keep them there.
- The Python, JavaScript/TypeScript and Go SDKs work over http. The .NET and
  Java SDKs need https:
  - With `protocol=https`, the emulator serves a self-signed certificate made
    for this sandbox. After every start it is added to the system trust store,
    and to Java's cacerts when `keytool` is on PATH. Run
    `cosmos-emulator trust` again after installing a JDK.
  - Node.js additionally needs
    `NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/cosmos-db-emulator.crt`.
    Python's `requests` additionally needs
    `REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`; the Python
    Cosmos SDK skips certificate checks for localhost and needs nothing.
  - Rely on that trust rather than turning certificate validation off in
    code, so the same code can later run against a real account.
  - If the endpoint is http and you need https,
    `COSMOS_EMULATOR_PROTOCOL=https cosmos-emulator restart` switches it until
    the sandbox restarts. Then run `eval "$(cosmos-emulator env)"`. To keep
    https, the user sets the kit arg `protocol=https`.
- The emulator does not enforce or support the following, so passing tests
  here prove nothing about them:
  - Authentication: any key is accepted.
  - Stored procedures, triggers and UDFs (not planned).
  - Request-unit charges, reading the database or container feed, and
    parallel cross-partition queries (not implemented yet).
  - Throughput (offers), users, permissions, client encryption keys and
    container updates: accepted, but nothing happens.
  - Custom indexing policies are accepted, but only DiskANN vector indexes
    take effect. Queries still work.
  - The .NET SDK's bulk execution.
- Other commands:
  - `cosmos-emulator status`: exits 0 when ready.
  - `cosmos-emulator logs`.
  - `cosmos-emulator restart`.
  - `cosmos-emulator shell -c 'ls'`: runs the Cosmos DB Shell inside the
    emulator.
  - `cosmos-emulator reset --yes`: deletes all data.
- Data is kept in a Docker volume across sandbox restarts, until `reset` or
  the sandbox is removed.
- The user can open Data Explorer from the host (port 1234, always http) and
  reach the gateway (port 8081), through the ports `sbx ports` lists.
