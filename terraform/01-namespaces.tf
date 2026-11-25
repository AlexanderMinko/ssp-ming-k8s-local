# 01-namespaces.tf — the app namespaces, platform-owned as on EKS (platform/04-cluster-singletons.tf).
# The Argo CD apps use CreateNamespace=false, so these must exist before the first sync.
#
# No StorageClass resource here: EKS needed `gp3` (EBS CSI driver). kind already ships a default class,
# `standard`, backed by the local-path provisioner — see var.storage_class.

resource "kubernetes_namespace_v1" "app" {
  for_each = toset(var.app_namespaces)

  metadata {
    name = each.value
  }
}
