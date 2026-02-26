# ==============================================================
# terraform/monitoring/main.tf
# Provisions the SpendWise Grafana dashboard via the
# grafana/grafana Terraform provider.
#
# The dashboard JSON is read from spendwise-dashboard.json
# in this same directory (path.module).
#
# Prerequisite: Grafana must be running and reachable at
#   var.grafana_url before this module is applied.
#
# Apply:
#   terraform init
#   terraform apply \
#     -var="grafana_url=http://<monitoring_ip>:3000" \
#     -var="grafana_api_key=<token>"
# ==============================================================

terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------
# Provider – authenticates to the running Grafana instance.
# Use a service-account token (Grafana ≥ 9) or a legacy API key.
# ---------------------------------------------------------------
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_api_key
}

# ---------------------------------------------------------------
# Data source – Prometheus (already provisioned by Ansible).
# We look it up so we can reference its UID if needed for
# alerting rules or annotations in future resources.
# ---------------------------------------------------------------
data "grafana_data_source" "prometheus" {
  name = "Prometheus"
}

# ---------------------------------------------------------------
# Grafana Dashboard – SpendWise RED Metrics + Infrastructure
#
# config_json is the raw Grafana dashboard JSON.
# file() reads spendwise-dashboard.json from this module's path.
# ---------------------------------------------------------------
resource "grafana_dashboard" "spendwise" {
  # Read the dashboard definition from the co-located JSON file.
  config_json = file("${path.module}/spendwise-dashboard.json")

  # Overwrite an existing dashboard with the same UID on re-apply.
  overwrite = true

  message = "Provisioned by Terraform – ${var.project_name} ${var.environment}"
}

# ---------------------------------------------------------------
# Grafana Folder – logical grouping for SpendWise dashboards.
# The dashboard above is placed in the General folder by default;
# create a dedicated folder here and reference it if preferred.
# ---------------------------------------------------------------
resource "grafana_folder" "spendwise" {
  title = "SpendWise – ${title(var.environment)}"
  uid   = "spendwise-${var.environment}"
}

# ---------------------------------------------------------------
# Grafana Dashboard in dedicated folder
# (Alternative to the root dashboard above – choose one approach)
# ---------------------------------------------------------------
# resource "grafana_dashboard" "spendwise_in_folder" {
#   folder      = grafana_folder.spendwise.id
#   config_json = file("${path.module}/spendwise-dashboard.json")
#   overwrite   = true
# }
