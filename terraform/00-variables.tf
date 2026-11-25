# 00-variables.tf — inputs of the local platform layer.

variable "kube_context" {
  description = "kubeconfig context of the kind cluster (kind names it kind-<cluster name>)."
  type        = string
  default     = "kind-ssp-local"

  # A guard, not a convenience: this layer must never run against EKS.
  validation {
    condition     = startswith(var.kube_context, "kind-")
    error_message = "kube_context must be a kind context (kind-...). This layer is for the local cluster only."
  }
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "app_namespaces" {
  description = "Namespaces the platform pre-creates for app workloads (same as platform/ on EKS)."
  type        = list(string)
  default     = ["production", "edge"]
}

variable "storage_class" {
  description = "StorageClass for every PVC. kind ships `standard` (local-path provisioner); on EKS this is gp3."
  type        = string
  default     = "standard"
}
