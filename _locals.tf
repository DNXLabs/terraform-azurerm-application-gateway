locals {
  prefix = var.name

  default_tags = {
    name      = var.name
    managedBy = "terraform"
  }

  tags = merge(local.default_tags, var.tags)

  rg_name = var.resource_group.create ? azurerm_resource_group.this["this"].name : data.azurerm_resource_group.existing[0].name
  rg_loc  = var.resource_group.create ? azurerm_resource_group.this["this"].location : (try(var.resource_group.location, null) != null ? var.resource_group.location : data.azurerm_resource_group.existing[0].location)

  # Resource names: use var.name directly as the full name
  agw_name = var.name

  sku_name_l = lower(var.appgw.sku_name)

  # Classify SKU
  is_v2  = contains(["standard_v2", "waf_v2"], local.sku_name_l)
  is_waf = startswith(local.sku_name_l, "waf")

  # Derive tier if user didn't pass (keeps it easy in YAML)
  derived_tier = local.is_v2 ? (
    local.sku_name_l == "standard_v2" ? "Standard_v2" : "WAF_v2"
  ) : (
    local.sku_name_l == "basic" ? "Basic" : (local.is_waf ? "WAF" : "Standard")
  )

  sku_tier = coalesce(try(var.appgw.sku_tier, null), local.derived_tier)

  # Names (avoid nulls)
  n_gateway_ip_configuration  = coalesce(try(var.appgw.names.gateway_ip_configuration, null),  "gwipcfg-001")
  n_frontend_ip_configuration = coalesce(try(var.appgw.names.frontend_ip_configuration, null), "fe-001")
  n_frontend_port             = coalesce(try(var.appgw.names.frontend_port, null),             "fe-port-001")

  n_backend_pool = coalesce(try(var.backend_pool.name, null), try(var.appgw.names.backend_address_pool, null), "be-001")
  n_probe        = coalesce(try(var.probe.name, null),        try(var.appgw.names.probe, null),               "probe-001")
  n_bhs          = coalesce(try(var.backend_http_settings.name, null), try(var.appgw.names.backend_http_settings, null), "bhs-001")
  n_listener     = coalesce(try(var.appgw.names.http_listener, null), "listener-001")
  n_rule         = coalesce(try(var.routing_rule.name, null), try(var.appgw.names.request_routing_rule, null), "rule-001")
  ssl_cert_name  = coalesce(try(var.listener.ssl_certificate.name, null), try(var.appgw.names.ssl_certificate, null), "sslcert-001")

  listener_protocol = coalesce(try(var.listener.protocol, null), "Http")
  is_https          = lower(local.listener_protocol) == "https"

  # Backend HTTP Settings port default
  bhs_port = coalesce(try(var.backend_http_settings.port, null), var.listener.port)

  # Azure requires host OR pick_host_name_from_backend_http_settings
  probe_pick_host = coalesce(
    try(var.probe.pick_host_name_from_backend_http_settings, null),
    try(var.probe.host, null) == null ? true : false
  )

  be_pick_host_from_address = coalesce(
    try(var.backend_http_settings.pick_host_name_from_backend_address, null),
    true
  )

  # Frontend type default: Standard_v2 => Public, others => Private
  frontend_type = lower(coalesce(try(var.appgw.frontend.type, null), "public"))

  is_public_frontend = local.frontend_type == "public"

  create_public_ip = local.is_public_frontend && coalesce(
    try(var.appgw.frontend.create_public_ip, null),
    try(var.appgw.frontend.public_ip_address_id, null) == null ? true : false
  )

  pip_name = "pip-${local.agw_name}"

  pip_sku   = coalesce(try(var.appgw.frontend.public_ip.sku, null), "Standard")
  pip_zones = try(var.appgw.frontend.public_ip.zones, null)

  public_ip_id = try(var.appgw.frontend.public_ip_address_id, null) != null ? var.appgw.frontend.public_ip_address_id : (local.create_public_ip ? azurerm_public_ip.this["this"].id : null)
  agw_zones = try(var.appgw.zones, null)
  waf_enabled = try(var.appgw.waf.enabled, false)
  diag_enabled = try(var.diagnostics.enabled, false) && (try(var.diagnostics.log_analytics_workspace_id, null) != null || try(var.diagnostics.storage_account_id, null) != null || try(var.diagnostics.eventhub_authorization_rule_id, null) != null)
}