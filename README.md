# ssp-ming-k8s-local

The SSP/Exchange stack on a local [kind](https://kind.sigs.k8s.io/) cluster, for Kubernetes practice
between EKS sessions. It costs nothing and starts in minutes.

This repo is isolated from the EKS repos (`ssp-ming-exchange-helm`, `ssp-ming-exchange-terraform`).
Nothing here can change the EKS stack.

## What replaces what

| On EKS | Here |
|---|---|
| Terraform `infra/` (VPC, NAT, node group, IAM) | `kind/cluster.yaml`: 1 control plane + 2 workers |
| AWS Load Balancer Controller + ALB | Envoy Gateway; the proxy is a NodePort mapped to `localhost:28080` |
| GatewayClass `alb` | GatewayClass `envoy`; the Gateway `edge/shared` keeps its name |
| `TargetGroupConfiguration` | off (`route.targetGroupConfiguration.enabled: false`) |
| Secrets Manager + Pod Identity | a Secret in namespace `secret-source`, read by ESO's Kubernetes provider |
| `gp3` / EBS CSI | kind's `standard` StorageClass (local-path) |
| ECR + CI | `scripts/build-images.sh`: `docker build` + `kind load` |
| metrics-server add-on | a Helm release (`terraform/04-metrics-server.tf`) |
| Argo CD on `values.yaml` only | Argo CD on `values.yaml` + `charts/envs/local/<chart>.yaml` |

Same as on EKS: ESO, Argo CD (App-of-Apps), VictoriaMetrics + Grafana, SigNoz + ClickHouse, the `k8s-infra`
log agent, and the three charts.

## Layout

| Path | Contents |
|---|---|
| `kind/cluster.yaml` | the cluster: nodes, Kubernetes version, the host port of the edge |
| `terraform/` | the platform layer, one root with local state (mirrors `platform/` on EKS) |
| `charts/` | `exchange`, `bidders`, `mongodb`: copies of the EKS charts plus one toggle |
| `charts/envs/local/` | every kind-specific value |
| `argocd/apps/` | the child Applications the root app creates |
| `scripts/` | cluster up/down, image build, port-forwards, admin passwords |

## Prerequisites

- Docker Desktop with **12 GiB memory or more** (Settings → Resources). ClickHouse alone uses 1–2 GB.
- `kind`, `kubectl`, `helm`, `terraform`.
- This repo pushed to `https://github.com/AlexanderMinko/ssp-ming-k8s-local` as a **public** repo.
  Argo CD in the cluster reads the charts from GitHub, not from your disk.

## Start

Run these from the repo root, in order.

1. Create the cluster.

   ```bash
   ./scripts/cluster-up.sh
   ```

2. Build the app images, load them into the nodes, and write their tags into the overlays.

   ```bash
   ./scripts/build-images.sh all
   ```

3. Commit and push the changed `charts/envs/local/*.yaml`.
4. Install the platform. The first apply takes about 10 minutes (SigNoz is slow).

   ```bash
   terraform -chdir=terraform init
   ```

   ```bash
   terraform -chdir=terraform apply
   ```

5. Check the apps and the edge.

   ```bash
   kubectl --context kind-ssp-local -n argocd get applications
   ```

   ```bash
   curl -s http://localhost:28080/actuator/health/readiness
   ```

   Expected: every Application `Synced` and `Healthy`, and `{"status":"UP"}` from curl.

## Daily use

| Task | Command |
|---|---|
| Open Grafana, Argo CD, SigNoz, VictoriaMetrics, Mongo | `./scripts/port-forward.sh` |
| Copy an admin password | `./scripts/retrieve-passwords.sh grafana` or `argocd` |
| Deploy an app change | `./scripts/build-images.sh exchange`, then commit and push the overlay |
| Deploy a chart or values change | edit, commit, push; Argo CD syncs within about 3 minutes |
| Delete everything | `./scripts/cluster-down.sh` |

SigNoz asks you to create the admin account at first login.

## Things that differ from EKS on purpose

- **One replica each**, small CPU requests. This is not a load-test cluster.
- **Tracing samples every request** (`1.0`); EKS uses `0.1` for 500 rps.
- **Volumes die with the cluster.** `cluster-down.sh` removes Mongo data, metrics and logs.
- **The Mongo password lives in the local Terraform state** in plain text. The state is git-ignored.

## What stays EKS-only

IAM and Pod Identity, ALB target groups and health checks, EBS zone binding, NAT, node groups, cost.

## Docker Desktop's built-in kind mode

Docker Desktop can create a kind cluster from its settings page. This repo uses the `kind` CLI instead:
`kind/cluster.yaml` pins the Kubernetes version and the host port in git, and the scripts need
`kind load`. Docker Desktop's cluster would need its own answer for both: the edge port mapping and the
image loading.

## Merging back into the EKS repos

The charts in `charts/` differ from the EKS charts by one toggle (`route.targetGroupConfiguration.enabled`,
default `true`). Check with:

```bash
diff -r ../ssp-ming-exchange-helm/charts/exchange charts/exchange
```

To merge: copy that toggle and `charts/envs/local/` into the helm repo. The Terraform root can move into
`ssp-ming-exchange-terraform/local/` unchanged.
