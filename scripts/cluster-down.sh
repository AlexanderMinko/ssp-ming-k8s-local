#!/usr/bin/env bash
# cluster-down.sh — delete the kind cluster AND the Terraform state that describes it.
#
# WHY both: the state lists Helm releases and objects inside the cluster. Once the cluster is gone, a
# leftover state makes every `terraform plan` fail ("connection refused") instead of planning a fresh install.
# Nothing is destroyed one by one: the cluster is three Docker containers, and no cloud resource exists.
#
# Usage: ./scripts/cluster-down.sh
set -euo pipefail

CLUSTER="ssp-local"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kind delete cluster --name "$CLUSTER"
rm -f "$ROOT/terraform/terraform.tfstate" "$ROOT/terraform/terraform.tfstate.backup"
echo "Deleted cluster $CLUSTER and the local Terraform state. All volumes (Mongo, metrics, logs) are gone."
