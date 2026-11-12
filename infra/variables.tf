variable "function_app_name" {
  description = "Existing backend products Function App. Its CORS settings are updated to allow the SPA."
  type        = string
}

variable "function_app_resource_group_name" {
  description = "Resource group containing the existing Function App."
  type        = string
}

# ---------------------------------------------------------------------------
# Optional: defaults suit the lab, override only if needed.
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription to deploy into (see `az account show`). Leave null to use the current az CLI subscription."
  type        = string
  default     = null
}

# The length limits below keep the generated storage account name within
# Azure's 24 characters: project + environment + 6-character suffix + "st".
variable "project" {
  description = "Project name, used as the first part of every resource name."
  type        = string
  default     = "products"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.project))
    error_message = "Must be 1-10 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name, used as the second part of every resource name, e.g. lab."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9]{1,6}$", var.environment))
    error_message = "Must be 1-6 characters: lowercase letters and digits only."
  }
}

variable "location" {
  description = "Azure region for new resources (must be permitted by your subscription's policy)."
  type        = string
  default     = "uksouth"
}

variable "api_base_url" {
  description = "Base URL of the products API, baked into the SPA. Defaults to https://<function_app_name>.azurewebsites.net/api/ - override if the Function App has a regional hostname."
  type        = string
  default     = null

  validation {
    # The SPA resolves 'products' against this URL, so without the trailing
    # slash the /api segment would be dropped.
    condition     = endswith(coalesce(var.api_base_url, "/"), "/")
    error_message = "Must end with a trailing slash."
  }
}
