module "swa_web_app" {
  source              = "../modules/swa"
  name_prefix         = "saintmalik-${local.environment}-webapp"
  dns_zone_name       = "saintmalik.me"
  dns_resource_group_name = local.resource_group_name
  resource_group_name = local.resource_group_name
  location            = local.location
  tags                = local.tags

  custom_domain = "${local.environment}.saintmalik.me"
}