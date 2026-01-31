data "azurerm_client_config" "current" {}

data "azurerm_key_vault_secret" "secrets" {
  for_each     = var.secrets_config
  name         = each.value
  key_vault_id = var.key_vault_id
}

data "azurerm_dns_zone" "existing" {
  count               = var.custom_domain != null ? 1 : 0
  name                = var.custom_domain.zone_name
  resource_group_name = var.custom_domain.dns_resource_group_name
}

variable "register_container_apps_provider" {
  description = "Whether to register the Microsoft.App provider"
  type        = bool
  default     = false
}

resource "azurerm_resource_provider_registration" "container_apps" {
  count = var.register_container_apps_provider ? 1 : 0
  name  = "Microsoft.App"

  lifecycle {
    ignore_changes = all
  }
}

resource "time_sleep" "provider_registration" {
  create_duration = "30s"
  depends_on      = [azurerm_resource_provider_registration.container_apps]
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name_prefix}-${var.app_name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "${var.name_prefix}-${var.app_name}-appinsights"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

resource "time_sleep" "before_environment" {
  create_duration = "30s"
  depends_on = [
    time_sleep.provider_registration,
    azurerm_log_analytics_workspace.main
  ]
}

resource "azurerm_container_app_environment" "main" {
  name                       = "${var.name_prefix}-${var.app_name}-environment"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id   = var.subnet_id
  tags                       = var.tags

  depends_on = [time_sleep.before_environment]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  all_secrets = toset([
    for k, v in merge(
      var.container_config.secrets,
      {
        for k, v in var.container_config.env_vars : v.secret => v.secret
        if v.type == "secret"
      }
    ) : v
  ])

  normalized_secrets = {
    for secret in local.all_secrets : lower(replace(secret, "_", "-")) => secret
  }

  custom_hostname = var.custom_domain != null ? "${var.custom_domain.subdomain}.${var.custom_domain.zone_name}" : null
}

resource "azurerm_container_app" "app" {
  name                         = "${var.name_prefix}-${var.app_name}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  registry {
    server   = var.registry_server
    identity = var.managed_identity_id
  }

  template {
    min_replicas = 1
    max_replicas = 10

    container {
      name    = var.app_name
      image   = var.container_config.api_image
      cpu     = tonumber(var.container_config.api_cpu)
      memory  = var.container_config.api_memory
      command = var.container_config.command
      args    = var.container_config.args

      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }

      dynamic "env" {
        for_each = var.enable_betterstack_forwarding ? [
          {
            name        = "BETTERSTACK_TOKEN"
            secret_name = "betterstack-token"
          },
          {
            name  = "BETTERSTACK_ENDPOINT"
            value = var.betterstack_endpoint
          }
        ] : []
        content {
          name        = env.value.name
          value       = lookup(env.value, "value", null)
          secret_name = lookup(env.value, "secret_name", null)
        }
      }

      dynamic "env" {
        for_each = var.database_config != null ? {
          "DB_HOST"      = var.database_config.host
          "DB_NAME"      = var.database_config.database_name
          "DB_USER"      = var.database_config.user
          "DB_AUTH_TYPE" = var.database_config.auth_type
          "DB_SSL_MODE"  = var.database_config.ssl_mode
          "DB_PORT"      = var.database_config.port
        } : {}
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.container_config.env_vars
        content {
          name        = env.key
          value       = env.value.type == "env" ? env.value.value : null
          secret_name = env.value.type == "secret" ? lower(replace(env.value.secret, "_", "-")) : null
        }
      }
    }
  }

  ingress {
    external_enabled = var.container_config.external_enabled
    target_port      = tonumber(var.container_config.api_target_port)

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  dynamic "secret" {
    for_each = local.normalized_secrets
    content {
      name  = secret.key
      value = data.azurerm_key_vault_secret.secrets[secret.value].value
    }
  }

  secret {
    name  = "appinsights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }

  dynamic "secret" {
    for_each = var.enable_betterstack_forwarding ? { "betterstack-token" = var.betterstack_source_token } : {}
    content {
      name  = secret.key
      value = secret.value
    }
  }

  tags = var.tags

  depends_on = [azurerm_application_insights.main]

  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      latest_revision_fqdn
    ]
  }
}

resource "azurerm_dns_cname_record" "custom_domain" {
  count               = var.custom_domain != null ? 1 : 0
  name                = var.custom_domain.subdomain
  zone_name           = data.azurerm_dns_zone.existing[0].name
  resource_group_name = var.custom_domain.dns_resource_group_name
  ttl                 = 300
  record              = azurerm_container_app.app.ingress[0].fqdn
  tags                = var.tags
}

resource "azurerm_dns_txt_record" "custom_domain_verification" {
  count               = var.custom_domain != null ? 1 : 0
  name                = "asuid.${var.custom_domain.subdomain}"
  zone_name           = data.azurerm_dns_zone.existing[0].name
  resource_group_name = var.custom_domain.dns_resource_group_name
  ttl                 = 300

  record {
    value = azurerm_container_app.app.custom_domain_verification_id
  }
  tags = var.tags
}

resource "null_resource" "add_custom_hostname" {
  count = var.custom_domain != null ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      if ! az containerapp hostname list \
        --resource-group ${azurerm_container_app.app.resource_group_name} \
        --name ${azurerm_container_app.app.name} \
        --query "[?name=='${local.custom_hostname}']" \
        --output tsv | grep -q "${local.custom_hostname}"; then
        az containerapp hostname add \
          --hostname ${local.custom_hostname} \
          --resource-group ${azurerm_container_app.app.resource_group_name} \
          --name ${azurerm_container_app.app.name}
      else
        echo "Hostname ${local.custom_hostname} already exists, skipping..."
      fi
    EOT
  }

  triggers = {
    hostname = local.custom_hostname
    app_name = azurerm_container_app.app.name
  }

  depends_on = [
    azurerm_dns_cname_record.custom_domain,
    azurerm_dns_txt_record.custom_domain_verification
  ]
}

resource "azapi_resource" "container_app_managed_certificate" {
  count     = var.custom_domain != null ? 1 : 0
  type      = "Microsoft.App/managedEnvironments/managedCertificates@2023-05-01"
  name      = "${var.name_prefix}-${var.app_name}-cert"
  parent_id = azurerm_container_app_environment.main.id
  location  = azurerm_container_app_environment.main.location

  body = {
    properties = {
      subjectName             = local.custom_hostname
      domainControlValidation = "CNAME"
    }
  }

  depends_on = [null_resource.add_custom_hostname]
}

resource "null_resource" "bind_certificate" {
  count = var.custom_domain != null ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      az containerapp hostname bind \
        --hostname ${local.custom_hostname} \
        --resource-group ${azurerm_container_app.app.resource_group_name} \
        --name ${azurerm_container_app.app.name} \
        --environment ${azurerm_container_app_environment.main.name} \
        --certificate ${azapi_resource.container_app_managed_certificate[0].name} \
        --validation-method CNAME
    EOT
  }

  depends_on = [azapi_resource.container_app_managed_certificate]
}

resource "azapi_resource" "db_setup_job" {
  count     = var.database_config != null ? 1 : 0
  type      = "Microsoft.App/jobs@2023-05-01"
  name      = "${var.name_prefix}-${var.app_name}-db-setup"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location

  body = {
    properties = {
      environmentId = azurerm_container_app_environment.main.id
      configuration = {
        triggerType    = "Manual"
        replicaTimeout = 300
        secrets = [
          {
            name  = "postgres-password"
            value = data.azurerm_key_vault_secret.secrets["PASSWORD"].value
          }
        ]
      }
      template = {
        containers = [
          {
            name  = "db-setup"
            image = "postgres:14"
            env = [
              { name = "PGHOST", value = var.database_config.host },
              { name = "PGPORT", value = var.database_config.port },
              { name = "PGDATABASE", value = var.database_config.database_name },
              { name = "PGUSER", value = "dbadmin" },
              { name = "PGSSLMODE", value = var.database_config.ssl_mode },
              { name = "PGPASSWORD", secretRef = "postgres-password" }
            ]
            command = ["/bin/sh"]
            args = [
              "-c",
              "sleep 30 && psql -c \"CREATE USER \\\"${var.managed_identity_name}\\\" WITH LOGIN;\" || echo \"User exists\" && psql -c \"ALTER USER \\\"${var.managed_identity_name}\\\" WITH CREATEDB;\" && psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${var.database_config.database_name} TO \\\"${var.managed_identity_name}\\\";\" && psql -c \"GRANT ALL PRIVILEGES ON SCHEMA public TO \\\"${var.managed_identity_name}\\\";\" && psql -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \\\"${var.managed_identity_name}\\\";\" && psql -c \"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \\\"${var.managed_identity_name}\\\";\" && echo \"Database setup completed\""
            ]
            resources = {
              cpu    = 0.25
              memory = "0.5Gi"
            }
          }
        ]
      }
    }
  }

  depends_on = [azurerm_container_app_environment.main]
}

resource "azapi_resource_action" "trigger_db_setup" {
  count       = var.database_config != null ? 1 : 0
  type        = "Microsoft.App/jobs@2023-05-01"
  resource_id = azapi_resource.db_setup_job[0].id
  action      = "start"
  method      = "POST"

  depends_on = [azapi_resource.db_setup_job]
}
