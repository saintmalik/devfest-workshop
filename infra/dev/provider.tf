terraform {
  required_version = ">= 1.10.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.40.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "2.7.0"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "saintmalikinfra"
    container_name       = "tfstate"
    key                  = "core/terraform.tfstate"
  }

  encryption {
    key_provider "azure_vault" "state_key" {
      vault_uri      = "https://saintmalikinfra-vault.vault.azure.net"
      vault_key_name = "tofu-state-key"
      key_length     = 32
    }

    method "aes_gcm" "state_encryption" {
      keys = key_provider.azure_vault.state_key
    }

    state {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "514ca6ed-1be2-4ae4-86d5-175a0ad4fb87"
}

provider "azapi" {}

# Define a resource group for all resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Outputs
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "resource_group_location" {
  value = azurerm_resource_group.main.location
}

output "resource_group_id" {
  value = azurerm_resource_group.main.id
}
