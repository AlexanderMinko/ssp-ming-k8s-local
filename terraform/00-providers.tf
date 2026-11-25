# 00-providers.tf — the platform layer of the LOCAL kind cluster (in-cluster resources only).
# It mirrors ssp-ming-exchange-terraform/platform/ with every AWS part replaced. No `aws` provider:
# kind has no IAM, no Pod Identity, no load balancer and no EBS.
#
# Run AFTER ./scripts/cluster-up.sh — the cluster must exist, as `platform/` needs `infra/` on EKS.

terraform {
  required_version = ">= 1.10"

  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.0" } # v2: same nested `kubernetes {}` block as platform/
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
    random     = { source = "hashicorp/random", version = "~> 3.0" }
  }

  # No backend block → LOCAL state: terraform.tfstate in this directory (git-ignored: it holds the generated
  # Mongo password in plain text). The state describes ONE cluster. ./scripts/cluster-down.sh deletes the cluster
  # and the state together; a state file that outlives its cluster makes every plan fail with "connection refused".
}

# Both providers read the kubeconfig and use the kind context BY NAME, never the current context:
# the same kubeconfig also holds the EKS context.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

# Every `kubectl apply` in this layer (terraform_data + local-exec) uses this prefix, for the same reason.
locals {
  kubectl = "kubectl --kubeconfig ${pathexpand(var.kubeconfig_path)} --context ${var.kube_context}"
}
