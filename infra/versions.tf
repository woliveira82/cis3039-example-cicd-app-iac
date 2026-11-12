terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State lives in Azure Storage so CI and local runs share it (otherwise each
  # CI run would start empty and create a new set of resources). Settings are
  # passed at init time: locally with -backend-config=backend.hcl (see
  # backend.hcl.example), in CI from repository variables.
  backend "azurerm" {}
}

provider "azurerm" {
  # Uses the current `az account show` subscription when left null.
  subscription_id = var.subscription_id

  # Don't attempt to register resource providers: restricted accounts often
  # aren't allowed to, and the attempt fails the run.
  resource_provider_registrations = "none"

  features {}
}
