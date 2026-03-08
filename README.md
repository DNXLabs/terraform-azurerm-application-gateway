# terraform-azurerm-application-gateway

Terraform module for creating and managing Azure Application Gateways with support for all SKU types (Basic, Standard_v2, WAF_v2), public/private frontends, HTTP/HTTPS listeners, WAF configuration, and optional managed identity for Key Vault certificate integration.

This module provides built-in validation to prevent common misconfigurations and supports both v1 (legacy) and v2 SKUs with automatic tier derivation.

## Features

- **Multiple SKU Support**: Basic, Standard_v2, WAF_v2 (v1 SKUs blocked by default)
- **Auto-Scaling**: Configurable autoscale for v2 SKUs (min/max capacity)
- **Public & Private Frontends**: Automatic Public IP creation or bring your own
- **HTTP & HTTPS Listeners**: HTTPS with inline certificates or Key Vault references
- **WAF Configuration**: Inline WAF with OWASP rule sets (Prevention/Detection modes)
- **Managed Identity**: UserAssigned identity support for Key Vault certificate access
- **Health Probes**: Configurable health probes with host name auto-pick
- **Backend HTTP Settings**: Cookie affinity, host name overrides, request timeouts
- **Routing Rules**: Basic request routing rules with priority support
- **Diagnostic Settings**: Optional Azure Monitor integration (Log Analytics, Storage, Event Hub)
- **Built-in Validations**: SKU/frontend/HTTPS/identity preconditions prevent misconfigurations
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support

## Usage

### Example 1 — Non-Prod (Basic HTTP)

A simple Application Gateway with Basic SKU, public IP, and HTTP listener for development/testing environments.

```hcl
module "appgateway" {
  source = "./modules/appgateway"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = true
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "my-app"
    environment = "development"
  }

  appgw = {
    sku_name  = "Basic"
    capacity  = 1
    subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-dev/subnets/snet-agw"

    frontend = {
      type             = "Public"
      create_public_ip = true
    }

    waf = {
      enabled = false
    }
  }

  backend_pool = {
    ip_addresses = ["10.0.1.10"]
  }

  listener = {
    port = 80
  }

  routing_rule = {
    priority = 100
  }
}
```

### Example 2 — Production (WAF_v2 with HTTPS)

A production-grade Application Gateway with WAF_v2 SKU, autoscale, HTTPS listener, and OWASP WAF rules.

```hcl
module "appgateway" {
  source = "./modules/appgateway"

  name = "contoso-prod-aue-web"

  resource_group = {
    create   = false
    name     = "rg-contoso-prod-aue-web-001"
    location = "australiaeast"
  }

  tags = {
    project     = "web-platform"
    environment = "production"
    compliance  = "pci-dss"
  }

  appgw = {
    sku_name = "WAF_v2"

    autoscale = {
      min_capacity = 2
      max_capacity = 10
    }

    subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-agw"

    frontend = {
      type             = "Public"
      create_public_ip = true
    }

    waf = {
      enabled          = true
      firewall_mode    = "Prevention"
      rule_set_version = "3.2"
    }

    identity = {
      type         = "UserAssigned"
      identity_ids = ["/subscriptions/xxxx/resourceGroups/rg-identity/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mi-appgw-prod"]
    }
  }

  backend_pool = {
    ip_addresses = ["10.0.1.10", "10.0.1.11"]
    fqdns        = ["api.contoso.com"]
  }

  probe = {
    protocol            = "Https"
    path                = "/health"
    interval            = 15
    timeout             = 15
    unhealthy_threshold = 3
    pick_host_name_from_backend_http_settings = true
  }

  backend_http_settings = {
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    cookie_based_affinity               = "Enabled"
    pick_host_name_from_backend_address = true
  }

  listener = {
    port     = 443
    protocol = "Https"

    ssl_certificate = {
      key_vault_secret_id = "https://kv-contoso-prod.vault.azure.net/secrets/wildcard-cert"
    }
  }

  routing_rule = {
    priority = 100
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/platform.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"

platform:
  app_gateways:
    agw-basic-001:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: false
        name: rg-managed-services-lab-aue-stg-001
        location: australiaeast

      appgw:
        sku_name: Basic
        capacity: 1
        subnet_name: snet-stg-agw
        frontend:
          type: Public
          create_public_ip: true
        waf:
          enabled: false

      backend_pool:
        ip_addresses:
          - 172.16.0.150

      listener:
        port: 80

      routing_rule:
        priority: 100

    agw-wafv2-001:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: false
        name: rg-managed-services-lab-aue-stg-001
        location: australiaeast

      appgw:
        sku_name: WAF_v2
        autoscale:
          min_capacity: 1
          max_capacity: 2
        subnet_name: snet-stg-agw
        frontend:
          type: Public
          create_public_ip: true
        waf:
          enabled: true
          firewall_mode: Prevention
          rule_set_version: "3.2"

      backend_pool:
        ip_addresses:
          - 172.16.0.150

      listener:
        port: 80

      routing_rule:
        priority: 130
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

data "azurerm_subnet" "agw" {
  name                 = local.workspace.network_lookup.agw_subnet_name
  virtual_network_name = local.workspace.network_lookup.vnet_name
  resource_group_name  = local.workspace.network_lookup.resource_group_name
}

module "appgateway" {
  for_each = try(local.workspace.platform.app_gateways, {})

  source = "./modules/appgateway"

  name           = each.key
  resource_group = each.value.resource_group
  tags           = try(each.value.tags, {})

  appgw = merge(each.value.appgw, {
    subnet_id = data.azurerm_subnet.agw.id
  })

  backend_pool         = each.value.backend_pool
  listener             = each.value.listener
  probe                = try(each.value.probe, {})
  backend_http_settings = try(each.value.backend_http_settings, {})
  routing_rule         = try(each.value.routing_rule, {})
  diagnostics          = try(each.value.diagnostics, {})
}
```

## SKU Reference

| SKU Name | Tier | Autoscale | WAF | Notes |
|----------|------|-----------|-----|-------|
| `Basic` | Basic | No | No | Lowest cost, fixed capacity |
| `Standard_v2` | Standard_v2 | Yes | No | Recommended for most workloads |
| `WAF_v2` | WAF_v2 | Yes | Yes | Web Application Firewall included |
| `Standard_Small`* | Standard | No | No | Legacy v1, blocked by default |
| `WAF_Medium`* | WAF | No | Yes | Legacy v1, blocked by default |

> **Note**: v1 SKUs (`Standard_Small`, `Standard_Medium`, `Standard_Large`, `WAF_Medium`, `WAF_Large`) are blocked by default due to Azure's retirement plan. Set `allow_v1_skus = true` to override.

## WAF Configuration

The WAF is only available with WAF-class SKUs (`WAF_v2`, `WAF_Medium`, `WAF_Large`):

```hcl
waf = {
  enabled          = true
  firewall_mode    = "Prevention"  # Prevention | Detection
  rule_set_version = "3.2"         # OWASP rule set version
}
```

## Frontend Configuration

### Public Frontend (default)

```hcl
frontend = {
  type             = "Public"
  create_public_ip = true  # Module auto-creates a Standard Static PIP
}
```

### Bring Your Own Public IP

```hcl
frontend = {
  type                 = "Public"
  public_ip_address_id = "/subscriptions/xxxx/.../publicIPAddresses/pip-existing"
}
```

## HTTPS Configuration

### Key Vault Certificate (recommended)

```hcl
listener = {
  port     = 443
  protocol = "Https"

  ssl_certificate = {
    key_vault_secret_id = "https://kv-prod.vault.azure.net/secrets/wildcard-cert"
  }
}

# Requires UserAssigned identity with access to the Key Vault
appgw = {
  identity = {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }
}
```

### Inline PFX Certificate

```hcl
listener = {
  port     = 443
  protocol = "Https"

  ssl_certificate = {
    data     = filebase64("certs/wildcard.pfx")
    password = "pfx-password"
  }
}
```

## Naming Convention

Resources are named using the prefix pattern: `{name}`

Example:
- Application Gateway: `agw-{name}-001`
- Public IP: `pip-agw-{name}-001`

## Outputs

| Name | Description |
|------|-------------|
| `application_gateway` | Application Gateway object with id, name, sku_name, sku_tier, frontend_type, public_ip_id |
| `public_ip` | Public IP object with id, name, ip (if created) |
| `identity` | Managed identity principal_id and tenant_id (if configured) |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration (create or use existing) | object | yes |
| `appgw` | Application Gateway configuration (SKU, autoscale, frontend, WAF, identity) | object | yes |
| `backend_pool` | Backend address pool (IP addresses and/or FQDNs) | object | yes |
| `listener` | HTTP/HTTPS listener configuration | object | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |
| `probe` | Health probe configuration | object | no |
| `backend_http_settings` | Backend HTTP settings | object | no |
| `routing_rule` | Request routing rule | object | no |
| `allow_v1_skus` | Allow legacy v1 SKUs (default: false) | bool | no |
| `enforce_public_frontend_for_standard_v2` | Enforce public frontend for Standard_v2 (default: true) | bool | no |

### Detailed Input Specifications

#### appgw

```hcl
object({
  name_suffix = optional(string, "001")
  name        = optional(string)

  sku_name = string  # Basic, Standard_v2, WAF_v2, etc.
  sku_tier = optional(string)  # Auto-derived from sku_name

  autoscale = optional(object({  # v2 SKUs only
    min_capacity = number
    max_capacity = number
  }))

  capacity  = optional(number)  # Non-v2 SKUs only
  subnet_id = string

  frontend = optional(object({
    type                 = optional(string)  # Public | Private
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
    firewall_mode    = optional(string, "Prevention")
    rule_set_version = optional(string, "3.2")
  }), {})

  identity = optional(object({
    type         = string        # UserAssigned
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
```

#### listener

```hcl
object({
  port     = number
  protocol = optional(string, "Http")  # Http | Https

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
```

#### backend_pool

```hcl
object({
  name         = optional(string)
  ip_addresses = optional(list(string))
  fqdns        = optional(list(string))
})
```

#### probe

```hcl
object({
  name                = optional(string)
  protocol            = optional(string, "Http")
  path                = optional(string, "/")
  interval            = optional(number, 30)
  timeout             = optional(number, 30)
  unhealthy_threshold = optional(number, 3)
  host                = optional(string)
  pick_host_name_from_backend_http_settings = optional(bool)
})
```

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.