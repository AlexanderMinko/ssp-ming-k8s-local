#!/usr/bin/env bash
# build-images.sh — build an app image, copy it into the kind nodes, and write its tag into the overlay.
# The local stand-in for the CI pipeline: build → push to ECR → bump-config commit.
#
# WHY `kind load`: a kind node is a container with its OWN containerd. An image in Docker Desktop's store
# is invisible to it until it is copied in. There is no registry.
# WHY a new tag per build: Argo CD and the kubelet act on a CHANGED tag. Rebuilding under the same tag
# changes no manifest, so nothing rolls — the same reason ECR tags are immutable.
#   clean work tree → tag = the commit's short SHA;  uncommitted changes → <sha>-dirty-<time>
#
# Usage:  ./scripts/build-images.sh exchange|bidders|all
# After:  commit and push charts/envs/local/<app>.yaml — Argo CD reads git, not your disk.
# A re-created cluster has empty nodes: run this again (the build is cached, the tag stays the same).
set -euo pipefail

CLUSTER="ssp-local"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/.." && pwd)"

usage() {
  echo "Usage: $0 exchange|bidders|all" >&2
  exit 2
}

build_one() {
  local app="$1"
  local source_dir="$WORKSPACE/ssp-ming-$app"
  local overlay="$ROOT/charts/envs/local/$app.yaml"
  [[ -f "$source_dir/Dockerfile" ]] || { echo "ERROR: no Dockerfile in $source_dir" >&2; exit 1; }

  local tag
  tag="$(git -C "$source_dir" rev-parse --short HEAD)"
  if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
    tag="$tag-dirty-$(date +%Y%m%d%H%M%S)"
  fi
  local image="ssp-ming/$app:$tag"

  echo "==> $app: building $image"
  docker build -t "$image" "$source_dir"
  echo "==> $app: loading into the kind nodes"
  kind load docker-image "$image" --name "$CLUSTER"

  # The overlay has exactly one `tag:` line.
  sed -i '' -E "s|^( *tag: ).*|\1\"$tag\" # OWNED BY scripts/build-images.sh|" "$overlay"
  echo "==> $app: wrote tag $tag to charts/envs/local/$app.yaml"
}

[[ $# -eq 1 ]] || usage
case "$1" in
  exchange | bidders) build_one "$1" ;;
  all)
    build_one exchange
    build_one bidders
    ;;
  *) usage ;;
esac

echo
echo "Next: review, commit and push charts/envs/local/ — Argo CD syncs the new tag from GitHub."
