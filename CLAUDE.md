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
- **Platform add-ons = Argo CD apps** (27/11/2026, option B1). `argocd/apps/` also holds
  `prometheus-operator-crds`, `victoria-metrics` (Helm release `vm`, so resources stay `vm-grafana`,
  `vmsingle-vm`), `signoz` and `k8s-infra`. Each pins the upstream chart (same version as EKS) and reads
  `$values/platform/<app>/values.yaml` (the EKS values) then `platform/envs/local/<app>.yaml`. Extra manifests
  sit in `platform/<app>/manifests/`. Terraform keeps only the bootstrap: namespaces, Envoy Gateway, ESO,
  metrics-server, Argo CD and the root app.
- **Sync order:** waves on the child Applications: CRDs `-2` → `victoria-metrics` `-1` → the rest `0`. The root
  app waits for each wave to be Healthy only because `terraform/05-argocd.tf` adds the Application health check
  to `argocd-cm`.
- **Apply mode:** `ServerSideApply=true` where a CRD exceeds 256 KiB (`victoria-metrics`,
  `prometheus-operator-crds`). Not on `signoz`: its migrator Job carries `Force=true,Replace=true`.
- **Gotchas found 27/11/2026:** an ExternalSecret in a server-side-applied app must spell out ESO's
  `remoteRef` defaults (`conversionStrategy`, `decodingStrategy`, `metadataPolicy`), or it stays OutOfSync
  even with `ServerSideDiff`. Renaming an Application deletes the old one, which runs the chart's pre-delete
  hooks (the VM chart's deletes every VMSingle/VMAgent). Removing a `helm_release` from a live cluster needs a
  `removed { lifecycle { destroy = false } }` block first, or `apply` uninstalls it.
- **Images:** no registry. `scripts/build-images.sh` builds from the sibling app repos, runs `kind load`, and
  rewrites the `tag:` line in the overlay. One new tag per build; never `latest`.
- **Edge:** Envoy Gateway. Gateway `edge/shared` (same name as on EKS), GatewayClass `envoy`, proxy Service
  NodePort 30080 → `http://localhost:28080`.
- **Secrets:** ESO Kubernetes provider. Source Secrets `secret-source/exchange-mongodb` and
  `secret-source/grafana-admin` (Terraform `random_password`), ClusterSecretStore `local-kubernetes`. No secret
  in git or chat.
- **Storage:** StorageClass `standard` (local-path). Volumes die with the cluster.
- **Observability:** same charts and versions as EKS (the VictoriaMetrics stack as Argo CD app `victoria-metrics` with Helm release `vm`, and the Argo CD apps `signoz` and `k8s-infra`), with
  smaller requests and volumes. Dashboards come from `ssp-ming-monitoring` on GitHub, as on EKS.
- **Log collection = one chain on the laptop, kind and EKS** (26/11/2026): operators json → time (`@timestamp`, gotime `2006-01-02T15:04:05.000Z07:00`) → trace → severity → `service_name` → resource `service.name` → `message` → body (kind and EKS add the container parser first). No flatten processor (added then dropped 26/11/2026, owner's choice): SigNoz stores the nested `payload` as one JSON string attribute, which its log view draws as an expandable tree, like ssp-backend's `testing_body`; search inside it by text (`payload CONTAINS 'gamma'`), not by field. The chain lives in `ssp-ming-exchange/observability/signoz/ingester/ingester.yaml` (local) and in `presets.logsCollection.operators` of `ssp-ming-exchange-terraform/platform/07-signoz.tf` (EKS) and `ssp-ming-k8s-local/platform/k8s-infra/values.yaml` (kind, an Argo CD app since 27/11/2026). Keep the three in step.

- **MCP servers:** `echo kind > ~/.ssp-ming-mcp-target`, run `scripts/port-forward.sh`, start a new session.
  The forwards use the `eks` ports of `ssp-ming-mcp/ports.json`. Mongo credentials come from the Secret
  `secret-source/exchange-mongodb`; the SigNoz key from the Keychain item `ssp-signoz-kind-api-key`.

## Rules

- The owner runs state-changing commands (`kind create/delete`, `terraform apply`, `git commit/push`,
  `kubectl apply/delete`). Read-only checks are fine (`helm template`, `terraform validate`, `kubectl get`).
- YAML: block style everywhere, no inline `{ }` flow maps.
- A local difference in a `.tf` file copied from `platform/` carries a `LOCAL:` comment.
- Chart versions stay equal to the EKS pins, so a local result transfers.
- Dates DD/MM/YYYY, metric units.

## Verified on a running cluster (25/11/2026)

- First `terraform apply` on kind: all five Argo CD apps `Synced` / `Healthy`, every pod `Running`.
- The edge: the `EnvoyProxy` patch pins NodePort 30080, and `http://localhost:28080` reaches the exchange.
- Memory: the full stack uses about 10 GiB of Docker Desktop's 13.6 GiB when idle.
- The add-on move (27/11/2026): a rebuild from zero synced the CRDs and VictoriaMetrics in wave order. SigNoz and
  `k8s-infra` were then adopted in place on the running cluster: no pod restarted except ZooKeeper, once
  (Argo CD's render drops `docker.io/` from its image). Result: all nine apps `Synced` / `Healthy`.
