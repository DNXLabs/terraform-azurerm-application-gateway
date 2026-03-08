resource "azurerm_resource_group" "this" {
  for_each = var.resource_group.create ? { "this" = var.resource_group } : {}
  name     = each.value.name
  location = each.value.location
  tags     = local.tags
}

resource "terraform_data" "validate_core" {
  input = {
    sku_name = var.appgw.sku_name
    sku_tier = local.sku_tier
  }

  lifecycle {
    precondition {
      condition     = lower(var.appgw.sku_name) != "standard"
      error_message = "sku_name='Standard' is not supported. Use one of: Basic, Standard_v2, WAF_v2, Standard_*, WAF_*."
    }

    precondition {
      condition     = local.is_v2 ? true : (try(var.appgw.autoscale, null) == null)
      error_message = "autoscale is only supported for Standard_v2 and WAF_v2. For other SKUs use appgw.capacity."
    }

    precondition {
      condition     = local.is_v2 ? true : (try(var.appgw.capacity, null) != null)
      error_message = "For sku_name Basic / Standard_* / WAF_* you must set appgw.capacity (autoscale is not supported)."
    }

    precondition {
      condition     = local.waf_enabled ? local.is_waf : true
      error_message = "waf.enabled=true requires a WAF SKU (WAF_v2 or WAF_*)."
    }
    precondition {
      condition = var.allow_v1_skus ? true : (contains(["basic", "standard_v2", "waf_v2"], lower(var.appgw.sku_name)))
      error_message = "This environment blocks v1 Application Gateway SKUs due to V1 retirement. Use sku_name: Basic, Standard_v2, or WAF_v2. (Set allow_v1_skus=true only if your subscription still supports v1.)"
    }
  }
}

resource "terraform_data" "validate_https" {
  input = { protocol = local.listener_protocol }

  lifecycle {
    precondition {
      condition = local.is_https ? (
        try(var.listener.ssl_certificate.key_vault_secret_id, null) != null ||
        try(var.listener.ssl_certificate.data, null) != null
      ) : true
      error_message = "listener.protocol=Https requires listener.ssl_certificate.key_vault_secret_id OR listener.ssl_certificate.data."
    }
  }
}

resource "terraform_data" "validate_identity" {
  input = { identity = try(var.appgw.identity, null) }

  lifecycle {
    precondition {
      condition = try(var.appgw.identity, null) == null ? true : (
        lower(var.appgw.identity.type) == "userassigned" &&
        length(try(var.appgw.identity.identity_ids, [])) > 0
      )
      error_message = "This environment supports only UserAssigned identity for Application Gateway. Set appgw.identity.type=UserAssigned and provide identity_ids."
    }
  }
}

resource "terraform_data" "validate_frontend" {
  input = {
    sku = var.appgw.sku_name
    fe  = local.frontend_type
    pip = local.public_ip_id
  }

  lifecycle {
    precondition {
      condition     = local.is_public_frontend
      error_message = "This environment requires a Public frontend (Public IP) for Application Gateway. Set appgw.frontend.type=Public (and use create_public_ip=true or pass public_ip_address_id)."
    }

    precondition {
      condition     = local.public_ip_id != null
      error_message = "frontend.type=Public requires a Public IP. Provide appgw.frontend.public_ip_address_id OR set appgw.frontend.create_public_ip=true."
    }
  }
}

resource "azurerm_public_ip" "this" {
  for_each = local.create_public_ip ? { "this" = true } : {}

  name                = local.pip_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  allocation_method = "Static"
  sku               = local.pip_sku
  zones             = local.pip_zones

  tags = local.tags
}

resource "azurerm_application_gateway" "this" {
  name                = local.agw_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  sku {
    name = var.appgw.sku_name
    tier = local.sku_tier

    # capacity belongs inside sku, only for non-v2
    capacity = local.is_v2 ? null : var.appgw.capacity
  }

  dynamic "autoscale_configuration" {
    for_each = local.is_v2 ? [1] : []
    content {
      min_capacity = var.appgw.autoscale.min_capacity
      max_capacity = var.appgw.autoscale.max_capacity
    }
  }

  dynamic "identity" {
    for_each = try(var.appgw.identity, null) == null ? [] : [var.appgw.identity]
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  gateway_ip_configuration {
    name      = local.n_gateway_ip_configuration
    subnet_id = var.appgw.subnet_id
  }

  frontend_ip_configuration {
    name = "${local.n_frontend_ip_configuration}-public"

    public_ip_address_id = local.public_ip_id
  }

  frontend_ip_configuration {
    name = "${local.n_frontend_ip_configuration}-private"

    subnet_id                     = var.appgw.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = coalesce(try(var.appgw.frontend_private_ip, null), "172.16.0.20")
  }

  frontend_port {
    name = local.n_frontend_port
    port = var.listener.port
  }

  dynamic "ssl_certificate" {
    for_each = local.is_https ? [1] : []
    content {
      name                = local.ssl_cert_name
      key_vault_secret_id = try(var.listener.ssl_certificate.key_vault_secret_id, null)
      data                = try(var.listener.ssl_certificate.data, null)
      password            = try(var.listener.ssl_certificate.password, null)
    }
  }

  backend_address_pool {
    name         = local.n_backend_pool
    ip_addresses = try(var.backend_pool.ip_addresses, null)
    fqdns        = try(var.backend_pool.fqdns, null)
  }

  probe {
    name     = local.n_probe
    protocol = try(var.probe.protocol, "Http")
    path     = try(var.probe.path, "/")

    host = try(var.probe.host, null)
    pick_host_name_from_backend_http_settings = local.probe_pick_host

    interval            = try(var.probe.interval, 30)
    timeout             = try(var.probe.timeout, 30)
    unhealthy_threshold = try(var.probe.unhealthy_threshold, 3)
  }

  backend_http_settings {
    name                  = local.n_bhs
    port                  = local.bhs_port
    protocol              = try(var.backend_http_settings.protocol, "Http")
    cookie_based_affinity = try(var.backend_http_settings.cookie_based_affinity, "Disabled")
    request_timeout       = try(var.backend_http_settings.request_timeout, 30)

    pick_host_name_from_backend_address = local.be_pick_host_from_address
    host_name                           = try(var.backend_http_settings.host_name, null)

    probe_name = local.n_probe
  }

  http_listener {
    name                           = local.n_listener
    frontend_ip_configuration_name = "${local.n_frontend_ip_configuration}-public"
    frontend_port_name             = local.n_frontend_port
    protocol                       = local.listener_protocol

    host_name  = try(var.listener.host_name, null)
    host_names = try(var.listener.host_names, null)

    require_sni          = local.is_https ? try(var.listener.require_sni, null) : null
    ssl_certificate_name = local.is_https ? local.ssl_cert_name : null
  }

  request_routing_rule {
    name                       = local.n_rule
    rule_type                  = "Basic"
    http_listener_name         = local.n_listener
    backend_address_pool_name  = local.n_backend_pool
    backend_http_settings_name = local.n_bhs
    priority                   = try(var.routing_rule.priority, 100)
  }

  dynamic "waf_configuration" {
    for_each = (local.is_waf && local.waf_enabled) ? [1] : []
    content {
      enabled          = true
      firewall_mode    = coalesce(try(var.appgw.waf.firewall_mode, null), "Prevention")
      rule_set_type    = "OWASP"
      rule_set_version = coalesce(try(var.appgw.waf.rule_set_version, null), "3.2")
    }
  }

  tags = local.tags

  depends_on = [
    terraform_data.validate_core,
    terraform_data.validate_https,
    terraform_data.validate_identity,
    terraform_data.validate_frontend
  ]
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diag_enabled ? { "this" = true } : {}

  name                           = "diag-${local.agw_name}"
  target_resource_id             = azurerm_application_gateway.this.id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayPerformanceLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }

  enabled_metric {
    category = "AllMetrics"
  }
}
