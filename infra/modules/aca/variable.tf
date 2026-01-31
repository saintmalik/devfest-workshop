
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

variable "subnet_id" {
  type        = string
  description = "Subnet ID from VNet module"
}

variable "managed_identity_name" {
  type        = string
  description = "Name of the managed identity for database permissions"
}

variable "managed_identity_id" {
  type        = string
  description = "ID of external managed identity to use"
}

variable "enable_sticky_sessions" {
  type    = bool
  default = false
}

variable "registry_server" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "container_config" {
  type = object({
    api_image       = string
    api_cpu         = string
    api_memory      = string
    api_target_port = string

    external_enabled     = bool
    ignore_image_changes = bool
    command              = list(string)
    args                 = list(string)
    secrets              = map(string)
    env_vars = map(object({
      type   = string
      secret = optional(string)
      value  = optional(string)
    }))
  })
}

variable "secrets_config" {
  type = map(string)
}

variable "key_vault_id" {
  type = string
}

variable "database_config" {
  type = object({
    host          = string
    database_name = string
    user          = string
    auth_type     = string
    ssl_mode      = string
    port          = string
  })
  default = null
}

variable "custom_domain" {
  type = object({
    zone_name               = string
    subdomain               = string
    dns_resource_group_name = string
  })
  default = null
}

variable "enable_betterstack_forwarding" {
  type    = bool
  default = false
}

variable "betterstack_source_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "betterstack_endpoint" {
  type    = string
  default = ""
}