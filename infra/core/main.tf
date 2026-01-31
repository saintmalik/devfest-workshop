locals {
  environment         = "core"
  location            = "East US 2"
  resource_group_name = "core-rg"
  tags = {
    Environment = local.environment
    ManagedBy   = "Opentofu"
  }
}

module "acr" {
  source              = "../modules/acr"
  registry_name       = "azuredevsecops"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
}

module "github_oidc" {
  source        = "../modules/github-oidc"
  identity_name = "saintmalik"
  location      = var.location
  tags = {
    env = "core"
  }

  repos = [
    "saintmalik/devfest-workshop",
    "saintmalik/blog.saintmalik.me",
  ]
}

resource "azurerm_role_assignment" "github_acr_push_prod" {
  scope                = module.acr.id
  role_definition_name = "AcrPush"
  principal_id         = module.github_oidc.prod_principal_id
}

resource "azurerm_role_assignment" "github_acr_push_nonprod" {
  scope                = module.acr.id
  role_definition_name = "AcrPush"
  principal_id         = module.github_oidc.nonprod_principal_id
}

resource "azurerm_role_assignment" "github_swa_contributor_prod" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Website Contributor"
  principal_id         = module.github_oidc.prod_principal_id
}

resource "azurerm_role_assignment" "github_swa_contributor_nonprod" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Website Contributor"
  principal_id         = module.github_oidc.nonprod_principal_id
}

resource "azurerm_role_assignment" "github_contributor_prod" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = module.github_oidc.prod_principal_id
}

resource "azurerm_role_assignment" "github_contributor_nonprod" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = module.github_oidc.nonprod_principal_id
}

output "github_prod_principal_id" { value = module.github_oidc.prod_principal_id }
output "github_prod_client_id" { value = module.github_oidc.prod_client_id }
output "github_nonprod_principal_id" { value = module.github_oidc.nonprod_principal_id }
output "github_nonprod_client_id" { value = module.github_oidc.nonprod_client_id }

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "notation" {
  name                = "saintmalik-artifacts-kv"
  location            = "East US 2"
  resource_group_name = "core-rg"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    certificate_permissions = [
      "Create",
      "Delete",
      "Get",
      "Import",
      "List",
      "Update",
      "Recover"
    ]

    key_permissions = [
      "Create",
      "Delete",
      "Get",
      "GetRotationPolicy",
      "List",
      "Sign",
      "Update",
      "Purge",
      "Recover",
      "SetRotationPolicy",
      "Backup",
      "Decrypt",
      "Encrypt",
      "Import",
      "Restore",
      "UnwrapKey",
      "Verify",
      "WrapKey",
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = module.github_oidc.prod_principal_id

    key_permissions = [
      "Get",
      "List",
      "Sign",
      "Verify"
    ]

    secret_permissions = [
      "Get"
    ]

    certificate_permissions = [
      "Get"
    ]
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = module.github_oidc.nonprod_principal_id

    key_permissions = [
      "Get",
      "List",
      "Sign",
      "Verify"
    ]

    secret_permissions = [
      "Get"
    ]

    certificate_permissions = [
      "Get"
    ]
  }
}

resource "azurerm_key_vault_certificate" "notation_cert" {
  name         = "notation-key"
  key_vault_id = azurerm_key_vault.notation.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }

    x509_certificate_properties {
      subject            = "CN=notation.saintmalik.me"
      validity_in_months = 12
      key_usage = [
        "digitalSignature"
      ]
      extended_key_usage = [
        "1.3.6.1.5.5.7.3.3" # Code Signing
      ]
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }
  }

  depends_on = [azurerm_key_vault.notation]
}


output "notation_cert_url" {
  value = "${azurerm_key_vault.notation.vault_uri}certificates/${azurerm_key_vault_certificate.notation_cert.name}/${azurerm_key_vault_certificate.notation_cert.version}"
}


output "current_client_object_id" {
  value       = data.azurerm_client_config.current.object_id
  description = "Object ID of the current client running Terraform"
}

output "tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Azure AD Tenant ID"
}
