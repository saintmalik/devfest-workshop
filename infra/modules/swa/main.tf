data "azurerm_dns_zone" "this" {
  name                = var.dns_zone_name
  resource_group_name = var.dns_resource_group_name
}

data "azurerm_dns_cname_record" "existing_www" {
  count               = var.custom_domain != null && var.dns_zone_name != null && var.custom_domain == var.dns_zone_name ? 1 : 0
  name                = "www"
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = data.azurerm_dns_zone.this.resource_group_name
}

resource "azurerm_static_web_app_custom_domain" "www_custom" {
  count             = var.custom_domain != null && var.dns_zone_name != null && var.custom_domain == var.dns_zone_name ? 1 : 0
  static_web_app_id = azurerm_static_web_app.this.id
  domain_name       = "www.${var.custom_domain}"
  validation_type   = "cname-delegation"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name_prefix}-ai"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  sampling_percentage = 10
  disable_ip_masking  = false
  tags                = var.tags
}

# variable "sku_tier" {
#   type        = string
#   description = "Tier for Static Web App (Free or Standard)"
#   default     = "Free"
# }

# variable "sku_size" {
#   type        = string
#   description = "SKU size (Free = Free, Standard = Standard)"
#   default     = "Free"
# }

variable "force_standard" {
  type        = bool
  description = "Force Standard SKU if Free is requested"
  default     = true
}

# fallback logic: if free is requested but no free slots remain, override manually
locals {
  effective_sku_tier = var.sku_tier == "Free" && var.force_standard ? "Standard" : var.sku_tier
  effective_sku_size = var.sku_tier == "Free" && var.force_standard ? "Standard" : var.sku_size
}

resource "azurerm_static_web_app" "this" {
  name                = "${var.name_prefix}-swa"
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_tier = local.effective_sku_tier
  sku_size = local.effective_sku_size

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
    "APPINSIGHTS_SAMPLING_PERCENTAGE"       = "10"
    "APPINSIGHTS_DISABLE_TELEMETRY"         = "false"
  }

  tags = var.tags
}


data "dns_a_record_set" "swa_ip" {
  count = var.custom_domain != null && var.dns_zone_name != null && var.custom_domain == var.dns_zone_name ? 1 : 0
  host  = azurerm_static_web_app.this.default_host_name
}

resource "azurerm_dns_a_record" "swa_root" {
  count               = var.custom_domain != null && var.dns_zone_name != null && var.custom_domain == var.dns_zone_name ? 1 : 0
  name                = "@"
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = data.azurerm_dns_zone.this.resource_group_name
  ttl                 = 300
  records             = data.dns_a_record_set.swa_ip[0].addrs
}

resource "azurerm_dns_cname_record" "swa_subdomain" {
  count               = var.custom_domain != null && var.dns_zone_name != null && var.custom_domain != var.dns_zone_name ? 1 : 0
  name                = trimsuffix(replace(var.custom_domain, ".${var.dns_zone_name}", ""), ".")
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = data.azurerm_dns_zone.this.resource_group_name
  ttl                 = 300
  record              = azurerm_static_web_app.this.default_host_name
}

resource "time_sleep" "wait_for_dns" {
  count           = var.custom_domain != null ? 1 : 0
  depends_on      = [azurerm_dns_cname_record.swa_subdomain, azurerm_dns_a_record.swa_root]
  create_duration = "60s"
}

resource "azurerm_static_web_app_custom_domain" "custom" {
  count             = var.custom_domain != null ? 1 : 0
  static_web_app_id = azurerm_static_web_app.this.id
  domain_name       = var.custom_domain
  validation_type   = var.custom_domain == var.dns_zone_name ? "dns-txt-token" : "cname-delegation"

  depends_on = [time_sleep.wait_for_dns]
}

resource "azurerm_dns_txt_record" "swa_validation" {
  count               = var.custom_domain != null && var.dns_zone_name != null && var.custom_domain == var.dns_zone_name && length(azurerm_static_web_app_custom_domain.custom[0].validation_token) > 0 ? 1 : 0
  name                = "asuid"
  zone_name           = data.azurerm_dns_zone.this.name
  resource_group_name = data.azurerm_dns_zone.this.resource_group_name
  ttl                 = 300

  record {
    value = azurerm_static_web_app_custom_domain.custom[0].validation_token
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

variable "tags" {
  type    = map(string)
  default = {}
}

variable "sku_tier" {
  type    = string
  default = "Free"
}

variable "sku_size" {
  type    = string
  default = "Free"
}

variable "custom_domain" {
  type    = string
  default = null
}

variable "dns_zone_name" {
  type    = string
}

variable "dns_resource_group_name" {
  type    = string
}

output "swa_url" {
  value = azurerm_static_web_app.this.default_host_name
}

output "swa_custom_domain" {
  value = var.custom_domain
}

output "application_insights_key" {
  value = azurerm_application_insights.this.instrumentation_key
}

output "application_insights_connection_string" {
  value = azurerm_application_insights.this.connection_string
  sensitive = true
}

output "validation_token" {
  value = var.custom_domain != null ? azurerm_static_web_app_custom_domain.custom[0].validation_token : null
  sensitive = true
}