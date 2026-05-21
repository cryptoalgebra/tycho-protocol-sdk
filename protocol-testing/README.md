# Protocol Testing

Rust-based integration testing framework for Tycho protocol implementations. See our full
docs [here](https://docs.propellerheads.xyz/tycho/for-dexs/protocol-integration/3.-testing).

## How to Run Locally

```bash
# Ensure PostgreSQL is running or start it via Docker
docker buildx build -f protocol-testing/postgres.Dockerfile -t protocol-testing-db:latest --load .
docker compose up db -d

# Export necessary env vars
export RPC_URL=..
export SUBSTREAMS_API_TOKEN=..

# If you use a local PostgreSQL instance, set the connection string if necessary
# By default, the binary will use `postgres://postgres:mypassword@localhost:5431/tycho_indexer_0`
# export DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# Run the tests for a specific package, defined in their integration_test.tycho.yaml file
# This type of tests are constrained to a specific block range defined
cargo run -- range --package "ethereum-balancer-v2"

# To run the full test, that will index from the protocol creation block to the latest:
cargo run -- full --package "ethereum-balancer-v2"

# Run tests on a specific chain. Default is Ethereum.
# Make sure to set the RPC_URL environment variable to match the target network.
cargo run -- range --package "base-aerodrome-slipstreams" --chain base

# Clean up
docker compose down
```

## How to Run with Docker

```bash
# Build the images, from the project root dir
docker buildx build -f protocol-testing/postgres.Dockerfile -t protocol-testing-db:latest --load .
docker buildx build -f protocol-testing/run.Dockerfile -t protocol-testing-test-runner:latest --load .

# Export necessary env vars
export RPC_URL=..
export SUBSTREAMS_API_TOKEN=..
export PROTOCOLS="ethereum-balancer-v2=weighted_legacy_creation ethereum-ekubo-v2"

# Start and show the test logs only
docker compose up -d && docker compose logs test-runner --follow

# Clean up
docker compose down
```

## Supernova V3 Indexer with Docker Compose

This source-based workflow runs a local Tycho indexer for the Blackhole/Supernova
`supernova-v3` integration from the checked-out code.

Runtime flow:

```text
External Substreams provider
  -> local supernova-v3 SPKG
  -> tycho-indexer
  -> Postgres
  -> Tycho RPC on :4242
  -> protocol-testing interactive REVM simulation
```

Docker Compose starts only Postgres and the indexer. The EVM VM is not a
separate service; `tycho-protocol-sdk interactive` creates the REVM instance
inside the `indexer` container when you request a quote.

Requirements:

- Docker Engine with Docker Compose v2 (`docker compose`)
- A valid `SUBSTREAMS_API_TOKEN`
- An Ethereum `RPC_URL` that supports `debug_storageRangeAt`

```bash
cd /path/to/tycho-protocol-sdk/protocol-testing
cp supernova-indexer.env.example .env
nano .env
```

Set at least:

```bash
RPC_URL=...
SUBSTREAMS_API_TOKEN=...
```

Run from source:

```bash
docker compose -f supernova-indexer.compose.yaml up -d --build
docker compose -f supernova-indexer.compose.yaml logs -f indexer
```

If only `.env` changed, rebuild is not required:

```bash
docker compose -f supernova-indexer.compose.yaml up -d --force-recreate indexer
```

If code changed, rebuild the indexer image:

```bash
docker compose -f supernova-indexer.compose.yaml build indexer
docker compose -f supernova-indexer.compose.yaml up -d --force-recreate indexer
```

Useful cleanup commands:

```bash
# Stop containers, keep indexed DB state
docker compose -f supernova-indexer.compose.yaml down

# Stop containers and delete indexed DB state
docker compose -f supernova-indexer.compose.yaml down -v
```

Expected indexer logs:

```text
Http and WS server started server_url="http://0.0.0.0:4242"
Extractor ethereum:supernova-v3-vm started!
SubstreamsSessionInit ... resolved_start_block=24468499
NewContract ...
SyncProgress ...
```

Tycho RPC is exposed on `http://localhost:4242`. Postgres is exposed on
`postgres://postgres:mypassword@localhost:5433/tycho_indexer_0`.

Quote check:

```bash
docker compose -f supernova-indexer.compose.yaml exec \
  -e RUST_LOG=protocol_testing=info,tycho_simulation=info \
  indexer \
  tycho-protocol-sdk interactive \
  --package supernova-v3 \
  --pool 0x2beb35e78c9427899353c41c96bcc96c5647ec63 \
  --token-in 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 \
  --token-out 0xdac17f958d2ee523a2206206994597c13d831ec7 \
  --amount 1000000
```

A successful quote confirms this path:

```text
Substreams -> tycho-indexer -> Postgres -> Tycho RPC -> REVM simulation
```

RPC provider note: `eth_blockNumber` and `eth_getStorageAt` are not enough for
this flow. Account extraction for `initialized_accounts` requires
`debug_storageRangeAt`; providers that hide the `debug_*` namespace will fail
during indexer startup.
