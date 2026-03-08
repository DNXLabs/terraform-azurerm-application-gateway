variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

# If true, Standard_v2 defaults to Public frontend and blocks Private-only.
# Set false only if your subscription supports private-only v2 gateways.
variable "enforce_public_frontend_for_standard_v2" {
  type        = bool
  default     = true
  description = "If true, Standard_v2 defaults to Public frontend and blocks Private-only. Set false if your tenant supports private-only v2 gateways."
}

variable "appgw" {
  description = "Application Gateway config (supports all provider sku_name values)."
  type = object({
    name_suffix = optional(string, "001")
    name        = optional(string)

    # sku_name must be one of the provider-allowed values:
    # Basic, Standard_Small, Standard_Medium, Standard_Large, Standard_v2, WAF_Medium, WAF_Large, WAF_v2
    sku_name = string
    sku_tier = optional(string)

    # v2 SKUs use autoscale; other SKUs use capacity
    autoscale = optional(object({
      min_capacity = number
      max_capacity = number
    }))

    capacity = optional(number)

    subnet_id = string

    # used only for Private frontend
    frontend_private_ip = optional(string)

    frontend = optional(object({
      type                 = optional(string) # Public | Private
      create_public_ip     = optional(bool)
      public_ip_address_id = optional(string)

      public_ip = optional(object({
        name  = optional(string)
        sku   = optional(string, "Standard")
        zones = optional(list(string))
      }))
    }))

    waf = optional(object({
      enabled          = optional(bool, false)
      firewall_mode    = optional(string, "Prevention") # Detection | Prevention
      rule_set_version = optional(string, "3.2")
    }), {})

    identity = optional(object({
      # AppGW accepts UserAssigned only
      type         = string               # UserAssigned
      identity_ids = list(string)
    }))

    names = optional(object({
      gateway_ip_configuration  = optional(string)
      frontend_ip_configuration = optional(string)
      frontend_port             = optional(string)
      backend_address_pool      = optional(string)
      probe                     = optional(string)
      backend_http_settings     = optional(string)
      http_listener             = optional(string)
      request_routing_rule      = optional(string)
      ssl_certificate           = optional(string)
    }))
  })
}

variable "backend_pool" {
  type = object({
    name         = optional(string)
    ip_addresses = optional(list(string))
    fqdns        = optional(list(string))
  })
}

variable "listener" {
  type = object({
    port     = number
    protocol = optional(string, "Http") # Http | Https

    host_name   = optional(string)
    host_names  = optional(list(string))
    require_sni = optional(bool)

    ssl_certificate = optional(object({
      name                = optional(string)
      key_vault_secret_id = optional(string)
      data                = optional(string)
      password            = optional(string)
    }))
  })
}

variable "probe" {
  type = object({
    name                = optional(string)
    protocol            = optional(string, "Http")
    path                = optional(string, "/")
    interval            = optional(number, 30)
    timeout             = optional(number, 30)
    unhealthy_threshold = optional(number, 3)

    host = optional(string)
    pick_host_name_from_backend_http_settings = optional(bool)
  })
  default = {}
}

variable "backend_http_settings" {
  type = object({
    name                    = optional(string)
    port                    = optional(number)
    protocol                = optional(string, "Http")
    request_timeout         = optional(number, 30)
    cookie_based_affinity   = optional(string, "Disabled")

    pick_host_name_from_backend_address = optional(bool)
    host_name                           = optional(string)
  })
  default = {}
}

variable "routing_rule" {
  type = object({
    name     = optional(string)
    priority = optional(number, 100)
  })
  default = {}
}

variable "allow_v1_skus" {
  type    = bool
  default = false
}