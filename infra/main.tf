data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

locals {
  location = coalesce(var.location, data.azurerm_resource_group.rg.location)

  # Files produced by `npm run build`; empty when dist_path is unset or not built yet.
  dist_files = var.dist_path == "" ? toset([]) : fileset(var.dist_path, "**")

  mime_types = {
    html  = "text/html"
    css   = "text/css"
    js    = "application/javascript"
    mjs   = "application/javascript"
    json  = "application/json"
    map   = "application/json"
    svg   = "image/svg+xml"
    png   = "image/png"
    jpg   = "image/jpeg"
    jpeg  = "image/jpeg"
    gif   = "image/gif"
    webp  = "image/webp"
    ico   = "image/x-icon"
    txt   = "text/plain"
    woff  = "font/woff"
    woff2 = "font/woff2"
    ttf   = "font/ttf"
  }

  # Static website endpoint without trailing slash, e.g. https://<name>.z33.web.core.windows.net
  web_origin = trimsuffix(azurerm_storage_account.app.primary_web_endpoint, "/")

  function_app_rg = var.function_app_resource_group_name != "" ? var.function_app_resource_group_name : var.resource_group_name
}

# 1. Storage Account suited for static sites
resource "azurerm_storage_account" "app" {
  name                     = var.storage_account_name
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = local.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

# 2. Enable static website (SPA: 404 falls back to index.html for client-side routing)
resource "azurerm_storage_account_static_website" "app" {
  storage_account_id = azurerm_storage_account.app.id
  index_document     = "index.html"
  error_404_document = "index.html"
}

# 3. Upload the built SPA to the $web container
resource "azurerm_storage_blob" "dist" {
  for_each = local.dist_files

  name                 = each.value
  storage_container_id = "${azurerm_storage_account.app.id}/blobServices/default/containers/$web"
  type                 = "Block"
  source               = "${var.dist_path}/${each.value}"
  content_md5          = filemd5("${var.dist_path}/${each.value}")
  content_type = lookup(
    local.mime_types,
    lower(element(split(".", each.value), length(split(".", each.value)) - 1)),
    "application/octet-stream"
  )

  depends_on = [azurerm_storage_account_static_website.app]
}

# 4. Add the storage site to CORS on the existing backend Function App.
# The Function App is managed elsewhere, so the origin is added/removed via the Azure CLI
# (same command as the README) instead of taking ownership of the whole site config.
resource "terraform_data" "function_cors" {
  count = var.function_app_name == "" ? 0 : 1

  input = {
    function_app   = var.function_app_name
    resource_group = local.function_app_rg
    origin         = local.web_origin
  }

  provisioner "local-exec" {
    command = "az functionapp cors add --name '${self.input.function_app}' --resource-group '${self.input.resource_group}' --allowed-origins '${self.input.origin}'"
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "az functionapp cors remove --name '${self.input.function_app}' --resource-group '${self.input.resource_group}' --allowed-origins '${self.input.origin}'"
  }
}
