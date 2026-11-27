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

      # LOCAL (27/11/2026, until EKS moves its add-ons to Argo CD too): the health check for Applications.
      # Argo CD 1.8 dropped it, so a child app counts as Healthy the moment it exists. With it, the root app
      # waits at each sync wave until the child apps of that wave are Healthy: CRDs (-2) → victoria-metrics (-1) → apps (0).
      cm = {
        "resource.customizations.health.argoproj.io_Application" = <<-EOT
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil then
            if obj.status.health ~= nil then
              hs.status = obj.status.health.status
              if obj.status.health.message ~= nil then
                hs.message = obj.status.health.message
              end
            end
          end
          return hs
        EOT
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

  # Everything the app charts reference must exist before the first sync: one unknown kind (HTTPRoute,
  # ExternalSecret) fails the WHOLE sync, and auto-sync doesn't retry the same commit.
  # The ServiceMonitor CRD and `monitoring` are no longer here (27/11/2026): Argo CD installs them itself,
  # in sync waves before the apps (argocd/apps/prometheus-operator-crds.yaml, victoria-metrics.yaml).
  depends_on = [
    helm_release.argocd,
    terraform_data.edge_gateway,       # HTTPRoute CRD + the Gateway `edge/shared`
    terraform_data.clustersecretstore, # ExternalSecret CRD + the store
    kubernetes_namespace_v1.app,       # `production`
  ]
}
