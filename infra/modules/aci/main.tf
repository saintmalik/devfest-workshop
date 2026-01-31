data "azurerm_client_config" "current" {}

data "azurerm_key_vault_secret" "secrets" {
  for_each     = var.secrets_config
  name         = each.value
  key_vault_id = var.key_vault_id
}

data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_resource_group_name
}

resource "azurerm_container_group" "main" {
  name                = "${var.name_prefix}-${var.app_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  ip_address_type     = var.container_config.external_enabled ? "Public" : "Private"
  dns_name_label      = var.container_config.external_enabled ? "${var.name_prefix}-${var.app_name}" : null
  os_type             = "Linux"
  restart_policy      = "Always"

  image_registry_credential {
    server   = var.registry_server
    username = var.registry_username
    password = data.azurerm_key_vault_secret.secrets["registry-password"].value
  }

  container {
    name   = var.app_name
    image  = data.azurerm_key_vault_secret.secrets[var.container_config.image_secret].value
    cpu    = tonumber(data.azurerm_key_vault_secret.secrets[var.container_config.cpu_secret].value)
    memory = tonumber(data.azurerm_key_vault_secret.secrets[var.container_config.memory_secret].value)

    commands = var.container_config.command

    environment_variables = {
      for k, v in var.container_config.env_vars : k => data.azurerm_key_vault_secret.secrets[v.secret].value
      if v.type == "value"
    }

    secure_environment_variables = {
      for k, v in var.container_config.env_vars : k => data.azurerm_key_vault_secret.secrets[v.secret].value
      if v.type == "secret"
    }

    ports {
      port     = tonumber(data.azurerm_key_vault_secret.secrets[var.container_config.target_port_secret].value)
      protocol = "TCP"
    }
  }

  tags = var.tags
}

resource "azurerm_dns_a_record" "main" {
  name                = var.subdomain
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = data.azurerm_dns_zone.main.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_group.main.ip_address]
  tags                = var.tags
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

variable "registry_server" {
  type = string
}

variable "registry_username" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "container_config" {
  type = object({
    image_secret         = string
    cpu_secret          = string
    memory_secret       = string
    target_port_secret  = string
    external_enabled    = bool
    command             = list(string)
    env_vars            = map(object({
      type   = string
      secret = string
    }))
  })
}

variable "secrets_config" {
  type = map(string)
}

variable "key_vault_id" {
  type = string
}

variable "subdomain" {
  type    = string
  default = "api"
}

variable "dns_zone_name" {
  type    = string
}

variable "dns_resource_group_name" {
  type    = string
  default = "dns-rg"
}

output "container_ip" {
  value = azurerm_container_group.main.ip_address
}

output "container_fqdn" {
  value = azurerm_container_group.main.fqdn
}

output "custom_domain_fqdn" {
  value = "${var.subdomain}.${var.dns_zone_name}"
}

output "app_url" {
  value = var.container_config.external_enabled ? "http://${var.subdomain}.${var.dns_zone_name}:${tonumber(data.azurerm_key_vault_secret.secrets[var.container_config.target_port_secret].value)}" : null
}