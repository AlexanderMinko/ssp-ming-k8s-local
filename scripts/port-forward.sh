#!/usr/bin/env bash
# port-forward.sh — open the UIs and data ports of the kind cluster on this Mac. Ctrl-C closes all of them.
#
# The forwards are the `eks` section of ../ssp-ming-mcp/ports.json — the SAME local ports as for EKS, on purpose:
# kind uses the same namespaces and Service names, so the MCP servers reach both clusters at the same addresses.
# Their target `kind` (echo kind > ~/.ssp-ming-mcp-target) only changes where the credentials come from.
# Never hardcode a port here. Cost: the kind and the EKS forwards can't be open together.
#
# The exchange is NOT here: it is reachable through the Gateway at http://localhost:28080 (kind/cluster.yaml).
#
# Usage: ./scripts/port-forward.sh
set -euo pipefail

CONTEXT="kind-ssp-local"
PORTS_FILE="$(cd "$(dirname "$0")/../.." && pwd)/ssp-ming-mcp/ports.json"
[[ -f "$PORTS_FILE" ]] || { echo "ERROR: $PORTS_FILE not found." >&2; exit 1; }

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

# One line per forward: name namespace service local_port remote_port.
while read -r name namespace service local_port remote_port; do
  kubectl --context "$CONTEXT" -n "$namespace" port-forward "svc/$service" "$local_port:$remote_port" >/dev/null &
  echo "$name → http://localhost:$local_port"
done < <(python3 -c '
import json, sys
for name, forward in json.load(open(sys.argv[1]))["eks"].items():
    print(name, forward["namespace"], forward["service"], forward["localPort"], forward["remotePort"])
' "$PORTS_FILE")

echo "Forwarding. Ctrl-C to stop."
wait
