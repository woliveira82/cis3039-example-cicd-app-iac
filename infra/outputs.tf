output "storage_account_name" {
  description = "Name of the static site storage account."
  value       = azurerm_storage_account.app.name
}

output "web_endpoint" {
  description = "URL of the static website (equivalent to `az storage account show --query primaryEndpoints.web`)."
  value       = azurerm_storage_account.app.primary_web_endpoint
}

output "uploaded_file_count" {
  description = "Number of files uploaded from dist_path to $web."
  value       = length(azurerm_storage_blob.dist)
}
