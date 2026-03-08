data "azurerm_resource_group" "existing" {
  count = var.resource_group.create ? 0 : 1
  name  = var.resource_group.name
}