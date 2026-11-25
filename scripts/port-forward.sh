#!/usr/bin/env bash
# port-forward.sh — open the UIs and data ports of the kind cluster on this Mac. Ctrl-C closes all of them.
#
# The exchange is NOT here: it is reachable through the Gateway at http://localhost:28080 (kind/cluster.yaml).
# Ports are the EKS forwards of ssp-ming-mcp/ports.json plus 10000, so both sets can be open at once.
# TODO: move this table into ssp-ming-mcp/ports.json as a `kind` section when the MCP servers get a `kind` target.
#
# Usage: ./scripts/port-forward.sh
set -euo pipefail

CONTEXT="kind-ssp-local"

# name | namespace | service | local port | remote port
FORWARDS=(
  "grafana|monitoring|vm-grafana|23000|80"
  "argocd|argocd|argocd-server|28090|80"
  "signoz|signoz|signoz|23301|8080"
  "vmsingle|monitoring|vmsingle-vm|28428|8428"
  "vmagent|monitoring|vmagent-vm|28429|8429"
  "mongo|production|mongodb|47017|27017"
)

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

for forward in "${FORWARDS[@]}"; do
  IFS='|' read -r name namespace service local_port remote_port <<<"$forward"
  kubectl --context "$CONTEXT" -n "$namespace" port-forward "svc/$service" "$local_port:$remote_port" >/dev/null &
  echo "$name → http://localhost:$local_port"
done

echo "Forwarding. Ctrl-C to stop."
wait
