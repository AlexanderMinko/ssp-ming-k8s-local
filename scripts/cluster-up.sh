#!/usr/bin/env bash
# cluster-up.sh — create the local kind cluster from kind/cluster.yaml (idempotent).
#
# WHY a script around one command: the pre-flight checks. The full stack (SigNoz + ClickHouse included)
# needs about 12 GiB in Docker Desktop; with less, pods get OOM-killed in ways that look like bugs.
#
# Usage: ./scripts/cluster-up.sh
# Next:  ./scripts/build-images.sh all   then   terraform -chdir=terraform apply
set -euo pipefail

CLUSTER="ssp-local" # = `name:` in kind/cluster.yaml → kubeconfig context kind-ssp-local
MIN_MEMORY_GIB=12
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for tool in docker kind kubectl; do
  command -v "$tool" >/dev/null || { echo "ERROR: $tool not found. Install it first (kind: brew install kind)." >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "ERROR: Docker is not running." >&2; exit 1; }

MEMORY_BYTES="$(docker info --format '{{.MemTotal}}')"
MEMORY_GIB=$((MEMORY_BYTES / 1024 / 1024 / 1024))
if ((MEMORY_GIB < MIN_MEMORY_GIB)); then
  echo "WARNING: Docker has ${MEMORY_GIB} GiB; the full stack needs about ${MIN_MEMORY_GIB} GiB." >&2
  echo "         Docker Desktop → Settings → Resources → Memory. Continuing anyway." >&2
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "Cluster $CLUSTER already exists."
else
  kind create cluster --config "$ROOT/kind/cluster.yaml"
fi

kubectl --context "kind-$CLUSTER" get nodes
