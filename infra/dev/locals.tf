locals {
  environment         = "dev"
  location            = "East US 2"
  resource_group_name = "saintmalik-${local.environment}-rg"
  tags = {
    Environment = local.environment
    ManagedBy   = "Opentofu"
  }


  repos = {
    api              = "api-repo"
    web-app          = "web-app-repo"
    community-portal = "community-portal-repo"
    company-portal   = "company-portal-repo"
  }
}
