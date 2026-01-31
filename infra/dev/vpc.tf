module "vnet" {
  source                    = "../modules/vnet"
  name_prefix               = "saintmalik-${local.environment}"
  resource_group_name       = local.resource_group_name
  location                  = local.location
  cidr                      = "10.0.0.0/16"
  azs                       = ["1", "2", "3"]
  private_subnets           = ["10.0.0.0/23", "10.0.2.0/24"]
  public_subnets            = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_private_networking = false
  tags                      = local.tags
}