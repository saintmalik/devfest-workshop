resource "azurerm_resource_group" "core" {
  name     = "core-rg"
  location = var.location
}

resource "azurerm_user_assigned_identity" "github_prod" {
  name                = "${var.identity_name}-github-prod"
  resource_group_name = azurerm_resource_group.core.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "github_nonprod" {
  name                = "${var.identity_name}-github-nonprod"
  resource_group_name = azurerm_resource_group.core.name
  location            = var.location
  tags                = var.tags
}

locals {
  prod_environments = ["production"]
  nonprod_environments = ["development", "staging"]

  prod_credentials = {
    for pair in flatten([
      for repo in var.repos : [
        for env in local.prod_environments : {
          key         = "${repo}-${env}"
          repo        = repo
          environment = env
        }
      ]
    ]) : pair.key => pair
  }

  nonprod_credentials = {
    for pair in flatten([
      for repo in var.repos : [
        for env in local.nonprod_environments : {
          key         = "${repo}-${env}"
          repo        = repo
          environment = env
        }
      ]
    ]) : pair.key => pair
  }
}

resource "azurerm_federated_identity_credential" "github_prod" {
  for_each = local.prod_credentials

  name                = "github-${each.value.repo}-${each.value.environment}"
  resource_group_name = azurerm_resource_group.core.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.github_prod.id
  subject             = "repo:${each.value.repo}:environment:${each.value.environment}"
}

resource "azurerm_federated_identity_credential" "github_nonprod" {
  for_each = local.nonprod_credentials

  name                = "github-${each.value.repo}-${each.value.environment}"
  resource_group_name = azurerm_resource_group.core.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.github_nonprod.id
  subject             = "repo:${each.value.repo}:environment:${each.value.environment}"
}

variable "identity_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "repos" {
  type = list(string)
}

output "prod_client_id" {
  value = azurerm_user_assigned_identity.github_prod.client_id
}

output "prod_principal_id" {
  value = azurerm_user_assigned_identity.github_prod.principal_id
}

output "nonprod_client_id" {
  value = azurerm_user_assigned_identity.github_nonprod.client_id
}

output "nonprod_principal_id" {
  value = azurerm_user_assigned_identity.github_nonprod.principal_id
}