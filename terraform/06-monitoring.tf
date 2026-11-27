# 06-monitoring.tf — the metrics stack moved to Argo CD (27/11/2026). Terraform no longer installs it.
#
#   was helm_release.prometheus_operator_crds   → argocd/apps/prometheus-operator-crds.yaml (wave -2)
#   was helm_release.victoria_metrics_k8s_stack → argocd/apps/victoria-metrics.yaml (wave -1), values in platform/victoria-metrics/
#
# Why: a values change is now a `git push`, and Argo CD reverts drift. Terraform keeps only what Argo CD
# depends on (namespaces, Envoy Gateway, ESO, Argo CD itself).
#
# Migrating a cluster that Terraform built BEFORE the move: don't just apply. Deleting a helm_release makes
# the next apply run `helm uninstall`, and the CRD chart's uninstall deletes every ServiceMonitor. Add a
# `removed { from = helm_release.<name>  lifecycle { destroy = false } }` block per release first, so
# Terraform forgets the release and Argo CD adopts it. (The kind cluster was rebuilt on 27/11/2026 instead.)
