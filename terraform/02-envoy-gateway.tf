# 02-envoy-gateway.tf — the edge. Replaces three EKS pieces at once:
#   platform/01-lb-controller.tf     AWS Load Balancer Controller (+ its IAM role and Pod Identity)
#   platform/02-gateway-api-crds.tf  the vendored Gateway API CRDs and the AWS-only CRDs
#   the ALB itself                   here: Envoy pods inside the cluster
#
# Gateway API splits the edge into three objects. Only the first differs between EKS and kind:
#   GatewayClass  WHO implements it   EKS: gateway.k8s.aws/alb → an ALB.   kind: Envoy Gateway → Envoy pods.
#   Gateway       the entry point     `edge/shared`, listener http :80 — the same name and listener as on EKS
#   HTTPRoute     the app's routing   charts/exchange — unchanged
# That is why the exchange chart needs no edge change: it only knows the Gateway's name.
#
# The chart installs the Gateway API CRDs and Envoy Gateway's own CRDs (subchart `crds`). Helm installs
# CRDs on FIRST install only — on a chart upgrade, apply the new CRDs yourself first.
resource "helm_release" "envoy_gateway" {
  name             = "eg"
  repository       = "oci://docker.io/envoyproxy" # an OCI registry, not an index.yaml repo: the chart is an image
  chart            = "gateway-helm"
  version          = "1.10.0" # Envoy Gateway v1.10.0 — verify latest: helm show chart oci://docker.io/envoyproxy/gateway-helm
  namespace        = "envoy-gateway-system"
  create_namespace = true
}

# EnvoyProxy (how the Envoy pods are exposed) + GatewayClass `envoy` + Gateway `edge/shared`.
# Custom resources whose CRDs come from the release above → kubernetes_manifest can't plan them;
# applied via kubectl, the same pattern as platform/04-cluster-singletons.tf.
resource "terraform_data" "edge_gateway" {
  triggers_replace = { manifest = filesha256("${path.module}/manifests/edge-gateway.yaml") }

  provisioner "local-exec" {
    command = "${local.kubectl} apply -f ${path.module}/manifests/edge-gateway.yaml"
  }

  depends_on = [
    helm_release.envoy_gateway,  # the CRDs and the controller
    kubernetes_namespace_v1.app, # the `edge` namespace
  ]
}
