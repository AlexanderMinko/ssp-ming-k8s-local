# 05-argocd.tf — Argo CD, the same chart and values as platform/05-argocd.tf on EKS.
# Terraform installs Argo CD and ONE Application (the root); Argo CD then owns the workloads.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.2.1" # same pin as platform/05-argocd.tf (Argo CD v3.4.5)
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    configs = {
      params = {
        # Plain HTTP for the API/UI: access is only via `kubectl port-forward` to localhost.
        "server.insecure" = true
      }
    }
  })]
}

# The root Application (App-of-Apps): it watches argocd/apps/ of THIS repo on GitHub.
# Argo CD reads git, never your disk — a chart or overlay change reaches the cluster only after `git push`.
resource "terraform_data" "argocd_root" {
  triggers_replace = { manifest = filesha256("${path.module}/manifests/root-app.yaml") }

  provisioner "local-exec" {
    command = "${local.kubectl} apply -f ${path.module}/manifests/root-app.yaml"
  }

  # Everything the app charts reference must exist before the first sync: one unknown kind (ServiceMonitor,
  # HTTPRoute, ExternalSecret) fails the WHOLE sync, and auto-sync doesn't retry the same commit.
  depends_on = [
    helm_release.argocd,
    helm_release.prometheus_operator_crds,   # ServiceMonitor CRD
    terraform_data.edge_gateway,             # HTTPRoute CRD + the Gateway `edge/shared`
    terraform_data.clustersecretstore,       # ExternalSecret CRD + the store
    kubernetes_namespace_v1.app,             # `production`
    helm_release.victoria_metrics_k8s_stack, # namespace `monitoring` + the Grafana sidecar (dashboards app)
  ]
}
