output "app_url" {
  value = var.custom_domain != null ? "https://${local.custom_hostname}" : "https://${azurerm_container_app.app.latest_revision_fqdn}"
}

output "container_app_id" {
  value = azurerm_container_app.app.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "application_insights_id" {
  value = azurerm_application_insights.main.id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}

output "application_insights_instrumentation_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}