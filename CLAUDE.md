# ssp-ming-k8s-local — the stack on a local kind cluster

Local Kubernetes practice between EKS sessions (created 25/11/2026). **Isolated on purpose:** nothing here
changes `ssp-ming-exchange-helm` or `ssp-ming-exchange-terraform`. It may merge into them later.

**Working mode: teach** — platform is the owner's blind spot. Explain before generating, one concept at a
time, lay out options, push back, no over-engineering.

## Contract

- **Cluster:** kind, name `ssp-local`, context **`kind-ssp-local`**, 1 control plane + 2 workers, Kubernetes 1.34
  (`kind/cluster.yaml`). Every script and every Terraform `kubectl` call names this context explicitly;
  `var.kube_context` rejects anything not starting with `kind-`. The same kubeconfig holds the EKS context.
- **Terraform:** one root, `terraform/`, **local state**. `scripts/cluster-down.sh` deletes the cluster and
  the state together. The state holds the generated Mongo password in plain text (git-ignored).
- **Charts:** `charts/{exchange,bidders,mongodb}` are copies of the EKS charts. Keep `values.yaml` and the
  templates equal to the EKS charts, apart from the toggle `route.targetGroupConfiguration.enabled`.
  **Every kind-specific value goes into `charts/envs/local/<chart>.yaml`.**
- **Argo CD:** root app → `argocd/apps/` of this repo on GitHub (`main`, public). Each app loads `values.yaml`
  then `../envs/local/<chart>.yaml`. Argo CD reads git: nothing deploys before `git push`.
- **Images:** no registry. `scripts/build-images.sh` builds from the sibling app repos, runs `kind load`, and
  rewrites the `tag:` line in the overlay. One new tag per build; never `latest`.
- **Edge:** Envoy Gateway. Gateway `edge/shared` (same name as on EKS), GatewayClass `envoy`, proxy Service
  NodePort 30080 → `http://localhost:28080`.
- **Secrets:** ESO Kubernetes provider. Source Secret `secret-source/exchange-mongodb`, ClusterSecretStore
  `local-kubernetes`. No secret in git or chat.
- **Storage:** StorageClass `standard` (local-path). Volumes die with the cluster.
- **Observability:** same charts and versions as EKS (VictoriaMetrics stack `vm`, SigNoz, `k8s-infra`), with
  smaller requests and volumes. Dashboards come from `ssp-ming-monitoring` on GitHub, as on EKS.

## Rules

- The owner runs state-changing commands (`kind create/delete`, `terraform apply`, `git commit/push`,
  `kubectl apply/delete`). Read-only checks are fine (`helm template`, `terraform validate`, `kubectl get`).
- YAML: block style everywhere, no inline `{ }` flow maps.
- A local difference in a `.tf` file copied from `platform/` carries a `LOCAL:` comment.
- Chart versions stay equal to the EKS pins, so a local result transfers.
- Dates DD/MM/YYYY, metric units.

## Not verified yet (written 25/11/2026 without a running cluster)

- The `EnvoyProxy` strategic-merge patch that pins NodePort 30080 (`terraform/manifests/edge-gateway.yaml`).
  Fields checked against the Envoy Gateway 1.10.0 CRD; the merge result is untested.
- Memory fit of the full stack in Docker Desktop.
- Remove an item here once a real `terraform apply` confirms it.
