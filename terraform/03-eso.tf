# 03-eso.tf — secrets. Replaces platform/03-eso.tf's AWS side:
#   AWS Secrets Manager secret `eks-dev/exchange/mongodb`  → a plain Secret `secret-source/exchange-mongodb`
#   IAM role + Pod Identity for ESO                         → a ServiceAccount + Role (RBAC)
#   ClusterSecretStore `aws-secretsmanager`                 → ClusterSecretStore `local-kubernetes`
#
# ESO itself and the charts' ExternalSecrets are the SAME as on EKS. An ExternalSecret says "give me key X
# from store S"; only the store knows where secrets come from. So the swap is two values in each overlay
# (charts/envs/local/*.yaml): the store's name and remoteKey.

resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.8.0" # same pin as platform/03-eso.tf
  namespace        = "external-secrets"
  create_namespace = true
}

# --- The "secrets manager": one namespace holding the source Secret ---
resource "kubernetes_namespace_v1" "secret_source" {
  metadata {
    name = "secret-source"
  }
}

# Generated once and kept in the state. No special characters: the apps put the password into a Mongo URI.
# ⚠️ Plain text in terraform.tfstate — fine for a throwaway laptop cluster, and why the state is git-ignored.
# Never reuse this pattern for a real secret (on EKS the value lives in Secrets Manager, outside Terraform).
resource "random_password" "mongodb" {
  length  = 24
  special = false
}

# Same two keys as the AWS secret, so the charts' `property:` fields match.
resource "kubernetes_secret_v1" "mongodb_source" {
  metadata {
    name      = "exchange-mongodb" # = externalSecrets.remoteKey in the overlays
    namespace = kubernetes_namespace_v1.secret_source.metadata[0].name
  }

  data = {
    MONGO_INITDB_ROOT_USERNAME = "root"
    MONGO_INITDB_ROOT_PASSWORD = random_password.mongodb.result
  }
}

# --- The identity the store reads with (the local stand-in for the ESO IAM role) ---
# ESO asks the API server for a short-lived token of this ServiceAccount and reads the Secret as it.
resource "kubernetes_service_account_v1" "eso_store_reader" {
  metadata {
    name      = "eso-store-reader"
    namespace = kubernetes_namespace_v1.secret_source.metadata[0].name
  }
}

# A Role, not a ClusterRole: read access to Secrets in `secret-source` ONLY — the RBAC version of
# "scope IAM to the exact ARN, never *".
resource "kubernetes_role_v1" "eso_store_reader" {
  metadata {
    name      = "eso-store-reader"
    namespace = kubernetes_namespace_v1.secret_source.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }

  # ESO validates the store by asking "what may I do here?" (a SelfSubjectRulesReview).
  rule {
    api_groups = ["authorization.k8s.io"]
    resources  = ["selfsubjectrulesreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "eso_store_reader" {
  metadata {
    name      = "eso-store-reader"
    namespace = kubernetes_namespace_v1.secret_source.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.eso_store_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.eso_store_reader.metadata[0].name
    namespace = kubernetes_namespace_v1.secret_source.metadata[0].name
  }
}

# ClusterSecretStore `local-kubernetes` — its CRD comes from the ESO chart, so it is applied via kubectl.
resource "terraform_data" "clustersecretstore" {
  triggers_replace = { manifest = filesha256("${path.module}/manifests/clustersecretstore.yaml") }

  provisioner "local-exec" {
    command = "${local.kubectl} apply -f ${path.module}/manifests/clustersecretstore.yaml"
  }

  depends_on = [
    helm_release.eso,
    kubernetes_role_binding_v1.eso_store_reader,
    kubernetes_secret_v1.mongodb_source,
  ]
}
