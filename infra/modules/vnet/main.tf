locals {
  final_private_subnets = length(var.private_subnets) > 0 ? var.private_subnets : [
    for i in range(length(var.azs)) : cidrsubnet(var.cidr, 8, i + 1)
  ]
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  address_space       = [var.cidr]
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = "${var.name_prefix}-aca-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.final_private_subnets[0]]
}

resource "azurerm_subnet" "database" {
  name                 = "${var.name_prefix}-db-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.final_private_subnets[1]]
  service_endpoints    = ["Microsoft.Storage"]
  delegation {
    name = "Microsoft.DBforPostgreSQL.flexibleServers"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "${var.name_prefix}-postgres-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
  lifecycle {
    ignore_changes = [name]
  }
}

variable "name_prefix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "private_subnets" {
  type    = list(string)
  default = []
}

variable "public_subnets" {
  type    = list(string)
  default = []
}

variable "enable_private_networking" {
  type        = bool
  description = "Enable private endpoints and DNS zones"
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

output "subnet_id" {
  value = azurerm_subnet.container_apps.id
}

output "database_subnet_id" {
  value = azurerm_subnet.database.id
}

output "vpc_id" {
  value = azurerm_virtual_network.main.id
}

output "vpc_cidr" {
  value = var.cidr
}

output "private_dns_zone_id" {
  value = var.enable_private_networking ? azurerm_private_dns_zone.postgres[0].id : null
}

output "virtual_network_name" {
  value = azurerm_virtual_network.main.name
}
