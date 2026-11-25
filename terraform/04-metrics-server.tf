# 04-metrics-server.tf — CPU/memory per pod, for `kubectl top` and the exchange's HPA.
# On EKS this is a cluster add-on (infra/); kind ships none, and without it the HPA shows
# `cpu: <unknown>/70%` and never scales.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0" # metrics-server v0.9.0 — verify latest: helm show chart metrics-server --repo https://kubernetes-sigs.github.io/metrics-server/
  namespace  = "kube-system"

  values = [yamlencode({
    # metrics-server scrapes every kubelet over HTTPS. A kind kubelet serves a self-signed certificate
    # that the cluster CA did not sign, so verification fails. Local-only setting; EKS kubelets have real ones.
    args = ["--kubelet-insecure-tls"]
  })]
}
