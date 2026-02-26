# ==============================================================
# terraform/monitoring/output.tf
# ==============================================================

output "dashboard_url" {
  description = "Direct URL to the provisioned SpendWise dashboard in Grafana."
  value       = "${var.grafana_url}/d/${jsondecode(grafana_dashboard.spendwise.config_json).uid}/spendwise-red-metrics-and-infrastructure"
}

output "dashboard_uid" {
  description = "Unique identifier of the provisioned Grafana dashboard."
  value       = jsondecode(grafana_dashboard.spendwise.config_json).uid
}

output "folder_uid" {
  description = "UID of the SpendWise Grafana folder."
  value       = grafana_folder.spendwise.uid
}
