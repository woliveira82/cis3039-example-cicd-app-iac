variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing resource group (<your-resource-group>)."
  type        = string
}

variable "location" {
  description = "Azure region (<permitted-location>). Defaults to the resource group's location when null."
  type        = string
  default     = null
}

variable "storage_account_name" {
  description = "Globally unique storage account name (<productappstoragename>): 3-24 lowercase letters and digits."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters, lowercase letters and digits only."
  }
}

variable "dist_path" {
  description = "Path to the built SPA (output of `npm run build`) to upload to $web. Leave empty to skip uploading."
  type        = string
  default     = "../dist"
}

variable "function_app_name" {
  description = "Existing backend products Function App (<your-backend-products-func>) to add the site to CORS. Leave empty to skip."
  type        = string
  default     = ""
}

variable "function_app_resource_group_name" {
  description = "Resource group of the Function App. Defaults to resource_group_name when empty."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}
