data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Recover",
      "Backup",
      "Purge",
      "Restore"
    ]
  }

  dynamic "access_policy" {
    for_each = var.additional_access_policies
    content {
      tenant_id = data.azurerm_client_config.current.tenant_id
      object_id = access_policy.value.object_id

      secret_permissions      = access_policy.value.secret_permissions
      key_permissions        = access_policy.value.key_permissions
      certificate_permissions = access_policy.value.certificate_permissions
    }
  }
}

variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "additional_access_policies" {
  type = list(object({
    object_id                   = string
    secret_permissions         = list(string)
    key_permissions           = list(string)
    certificate_permissions   = list(string)
  }))
  default = []
}

output "id" {
  value = azurerm_key_vault.main.id
}

output "vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "name" {
  value = azurerm_key_vault.main.name
}