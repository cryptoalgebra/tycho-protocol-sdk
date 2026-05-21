#!/bin/bash
set -euo pipefail

: "${DATABASE_URL:=postgres://postgres:mypassword@db:5432/tycho_indexer_0}"
: "${RPC_URL:?RPC_URL must be set}"
: "${SUBSTREAMS_API_TOKEN:?SUBSTREAMS_API_TOKEN must be set}"
: "${CHAIN:=ethereum}"
: "${PROTOCOL_SYSTEM:=supernova-v3-vm}"
: "${PROTOCOL_TYPE:=supernova_algebra_pool_vm}"
: "${MODULE_NAME:=map_pool_events}"
: "${START_BLOCK:=24468499}"
: "${RETENTION_HORIZON:=2028-01-01T00:00:00}"
: "${EXTRACTORS_CONFIG:=/app/extractors.yaml}"

export AUTH_API_KEY="${AUTH_API_KEY:-dummy}"
export RUST_LOG="${RUST_LOG:-error,tycho_indexer=info,tycho_client=info}"

SPKG="/app/substreams/supernova-v3/supernova-v3-v0.1.0.spkg"
SUBSTREAMS_YAML="/app/substreams/supernova-v3/supernova-v3.yaml"

if [ ! -f "$SPKG" ]; then
  echo "Packing Supernova V3 substream..."
  (cd /app/substreams/supernova-v3 && substreams pack "$SUBSTREAMS_YAML")
fi

python3 - <<'PY'
from pathlib import Path

base = Path("/app/protocol-testing/extractors.yaml").read_text()
integration = Path("/app/substreams/supernova-v3/integration_test.tycho.yaml").read_text()

accounts = []
in_accounts = False
for line in integration.splitlines():
    stripped = line.strip()
    if stripped.startswith("initialized_accounts:"):
        in_accounts = True
        continue
    if in_accounts:
        if stripped.startswith("tests:"):
            break
        if stripped.startswith("-"):
            value = stripped[1:].split("#", 1)[0].strip().strip('"').strip("'")
            if value:
                accounts.append(value)

if "dci_plugin:" not in base:
    base = base.rstrip() + "\n    dci_plugin:\n      type: rpc\n"

if accounts and "initialized_accounts:" not in base:
    lines = base.splitlines()
    insert_at = next((i for i, line in enumerate(lines) if line.strip() == "dci_plugin:"), len(lines))
    account_lines = ["    initialized_accounts:"]
    account_lines.extend(f'      - "{account}"' for account in accounts)
    account_lines.append("    initialized_accounts_block: 24468499")
    lines[insert_at:insert_at] = account_lines
    base = "\n".join(lines) + "\n"

Path("/app/extractors.yaml").write_text(base)
PY

echo "Starting tycho-indexer for $PROTOCOL_SYSTEM from block $START_BLOCK"

exec tycho-indexer \
  --database-url "$DATABASE_URL" \
  --endpoint "https://mainnet.eth.streamingfast.io:443" \
  index \
  --extractors-config "$EXTRACTORS_CONFIG" \
  --chains "$CHAIN" \
  --retention-horizon "$RETENTION_HORIZON"
