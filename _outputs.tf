output "application_gateway" {
  value = {
    id            = azurerm_application_gateway.this.id
    name          = azurerm_application_gateway.this.name
    sku_name      = var.appgw.sku_name
    sku_tier      = local.sku_tier
    frontend_type = local.frontend_type
    public_ip_id  = local.public_ip_id
  }
}

output "public_ip" {
  value = local.create_public_ip ? {
    id   = azurerm_public_ip.this["this"].id
    name = azurerm_public_ip.this["this"].name
    ip   = azurerm_public_ip.this["this"].ip_address
  } : null
}

output "identity" {
  value = try({
    principal_id = azurerm_application_gateway.this.identity[0].principal_id
    tenant_id    = azurerm_application_gateway.this.identity[0].tenant_id
  }, null)
}