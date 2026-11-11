output "resource_group_name" {
  description = "Generated resource group name."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "Generated storage account name."
  value       = azurerm_storage_account.web.name
}

output "website_url" {
  description = "Public URL of the deployed SPA."
  value       = azurerm_storage_account.web.primary_web_endpoint
}

output "api_base_url" {
  description = "API base URL baked into the SPA."
  value       = local.api_base_url
}
