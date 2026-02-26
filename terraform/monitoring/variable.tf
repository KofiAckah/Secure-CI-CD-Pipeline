# ==============================================================
# terraform/monitoring/variable.tf
# Variables for the Grafana dashboard provisioning module.
#
# Usage:
#   cd terraform/monitoring
#   terraform init
#   terraform apply \
#     -var="grafana_url=http://<monitoring_server_ip>:3000" \
#     -var="grafana_api_key=<service-account-token>"
# ==============================================================

variable "grafana_url" {
  description = "Base URL of the Grafana instance (e.g. http://52.57.3.18:3000)"
  type        = string
}

variable "grafana_api_key" {
  description = "Grafana service-account token or API key with Editor or Admin role."
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Project identifier used in resource tags."
  type        = string
  default     = "spendwise"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)."
  type        = string
  default     = "dev"
}
