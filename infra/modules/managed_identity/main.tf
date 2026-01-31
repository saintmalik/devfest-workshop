resource "azurerm_user_assigned_identity" "main" {
  name                = "${var.name_prefix}-${var.app_name}-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

variable "name_prefix" {
  type = string
}

variable "app_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "acr_id" {
  type = string
}

output "id" {
  value = azurerm_user_assigned_identity.main.id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.main.principal_id
}

output "client_id" {
  value = azurerm_user_assigned_identity.main.client_id
}

output "name" {
  value = azurerm_user_assigned_identity.main.name
}