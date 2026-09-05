# ─────────────────────────────────────────────────────────────
# Locals — flatten the VNET map for cross-product iteration
# (e.g. one DNS zone per VNET × zone type)
# ─────────────────────────────────────────────────────────────
locals {
  dns_zone_names = {
    websites = "privatelink.azurewebsites.net"
    sql      = "privatelink.database.windows.net"
    blob     = "privatelink.blob.core.windows.net"
    search   = "privatelink.search.windows.net"
    file     = "privatelink.file.core.windows.net"
    queue    = "privatelink.queue.core.windows.net"
    table    = "privatelink.table.core.windows.net"
  }

  # Cross-product for DNS zone → VNET links: { "primary-websites" = { role = "primary", zone_key = "websites", ... }, ... }
  dns_zone_vnet_links = merge([
    for role, vnet in var.vnets : {
      for zone_key, zone_name in local.dns_zone_names :
      "${role}-${zone_key}" => {
        role      = role
        zone_key  = zone_key
        zone_name = zone_name
      }
    }
  ]...)
}

# ─────────────────────────────────────────────────────────────
# Resource Groups — one per VNET (primary / secondary)
# ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "this" {
  for_each = var.vnets

  name     = each.value.resource_group_name
  location = each.value.location
  tags     = var.tags
}

# ─────────────────────────────────────────────────────────────
# Shared Resource Group — Enterprise Policy & Private DNS Zones
# ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "shared" {
  name     = var.shared_resource_group.name
  location = var.shared_resource_group.location
  tags     = var.tags
}

# ─────────────────────────────────────────────────────────────
# Network Security Groups — one per VNET, common rules
# NSGs are regional so each VNET needs its own, but the
# rule definitions are identical.
# ─────────────────────────────────────────────────────────────
resource "azurerm_network_security_group" "powerplatform" {
  for_each = var.vnets

  name                = "nsg-${each.value.subnet_name}-${each.key}"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  tags                = var.tags
}

# Allow outbound HTTPS (required for Power Platform connectors)
resource "azurerm_network_security_rule" "allow_https_outbound" {
  for_each = var.vnets

  name                        = "Allow-HTTPS-Outbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this[each.key].name
  network_security_group_name = azurerm_network_security_group.powerplatform[each.key].name
}

# Allow outbound SQL (1433) for SQL connector over VNET
resource "azurerm_network_security_rule" "allow_sql_outbound" {
  for_each = var.vnets

  name                        = "Allow-SQL-Outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.this[each.key].name
  network_security_group_name = azurerm_network_security_group.powerplatform[each.key].name
}

# ─────────────────────────────────────────────────────────────
# Virtual Networks — primary (eastus) and secondary (westus)
# ─────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "this" {
  for_each = var.vnets

  name                = each.value.vnet_name
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  address_space       = each.value.vnet_address_space
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────
# Delegated Subnets — Power Platform VNET injection
# Each VNET gets its own delegated subnet.
# ─────────────────────────────────────────────────────────────
resource "azurerm_subnet" "powerplatform" {
  for_each = var.vnets

  name                 = each.value.subnet_name
  resource_group_name  = azurerm_resource_group.this[each.key].name
  virtual_network_name = azurerm_virtual_network.this[each.key].name
  address_prefixes     = each.value.subnet_address_prefix

  delegation {
    name = "power-platform-delegation"

    service_delegation {
      name = "Microsoft.PowerPlatform/enterprisePolicies"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "powerplatform" {
  for_each = var.vnets

  subnet_id                 = azurerm_subnet.powerplatform[each.key].id
  network_security_group_id = azurerm_network_security_group.powerplatform[each.key].id
}

# ─────────────────────────────────────────────────────────────
# NAT Gateways — one per VNET
# Provides a static outbound IP for all egress traffic from
# VNET-injected connectors — useful for firewall allow-listing.
# ─────────────────────────────────────────────────────────────
resource "azurerm_public_ip" "nat" {
  for_each = var.vnets

  name                = "pip-nat-${each.value.vnet_name}"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "powerplatform" {
  for_each = var.vnets

  name                    = "natgw-${each.value.vnet_name}"
  location                = azurerm_resource_group.this[each.key].location
  resource_group_name     = azurerm_resource_group.this[each.key].name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "powerplatform" {
  for_each = var.vnets

  nat_gateway_id       = azurerm_nat_gateway.powerplatform[each.key].id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "powerplatform" {
  for_each = var.vnets

  subnet_id      = azurerm_subnet.powerplatform[each.key].id
  nat_gateway_id = azurerm_nat_gateway.powerplatform[each.key].id
}

# ─────────────────────────────────────────────────────────────
# Endpoints Subnets — one per VNET
# Hosts private endpoints for backend services
# (Azure Functions, SQL Server, etc.)
# ─────────────────────────────────────────────────────────────
resource "azurerm_subnet" "endpoints" {
  for_each = var.vnets

  name                 = each.value.endpoints_subnet_name
  resource_group_name  = azurerm_resource_group.this[each.key].name
  virtual_network_name = azurerm_virtual_network.this[each.key].name
  address_prefixes     = each.value.endpoints_subnet_address_prefix

  private_endpoint_network_policies = "Disabled"
}

# ─────────────────────────────────────────────────────────────
# Private DNS Zones — centralised in the shared resource group
# One set of zones shared across all VNETs.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "this" {
  for_each = local.dns_zone_names

  name                = each.value
  resource_group_name = azurerm_resource_group.shared.name
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────
# Private DNS Zone — Company Internal Domain
# Fallback to internet is DISABLED so internal names never
# leak to public resolvers.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "internal" {
  name                = var.internal_domain_name
  resource_group_name = azurerm_resource_group.shared.name
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────
# DNS Zone → VNET Links
# Each zone is linked to every VNET so all can resolve
# private DNS names.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.dns_zone_vnet_links

  name                  = "${var.vnets[each.value.role].vnet_name}-${each.value.zone_key}-link"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone_key].name
  virtual_network_id    = azurerm_virtual_network.this[each.value.role].id
  registration_enabled  = false
  resolution_policy     = "NxDomainRedirect"
  tags                  = var.tags
}

# ─────────────────────────────────────────────────────────────
# Internal Domain DNS Zone → VNET Links
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
  for_each = var.vnets

  name                  = "${each.value.vnet_name}-internal-link"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.this[each.key].id
  registration_enabled  = false
  tags                  = var.tags
}

# ─────────────────────────────────────────────────────────────
# Power Platform Enterprise Policy (NetworkInjection kind)
# A single policy connected to both VNETs. Uses AzAPI because
# Microsoft.PowerPlatform is not in AzureRM.
# Placed in the shared resource group.
# ─────────────────────────────────────────────────────────────
resource "azapi_resource" "enterprise_policy" {
  response_export_values = ["properties.systemId"]
  type                   = "Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview"
  name                   = var.enterprise_policy_name
  location               = var.enterprise_policy_location
  parent_id              = azurerm_resource_group.shared.id
  tags                   = var.tags

  body = {
    kind = "NetworkInjection"
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      networkInjection = {
        virtualNetworks = [
          for role, vnet in var.vnets : {
            id = azurerm_virtual_network.this[role].id
            subnet = {
              name = azurerm_subnet.powerplatform[role].name
            }
          }
        ]
      }
    }
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.powerplatform
  ]
}

# ─────────────────────────────────────────────────────────────
# Entra ID Security Group — Power Platform Admins
# The Enterprise Policy is shared with this group so its
# members can manage VNET injection.
# ─────────────────────────────────────────────────────────────
resource "azuread_group" "power_platform_admins" {
  display_name     = var.power_platform_admin_group_name
  security_enabled = true
  description      = "Power Platform Admins — granted Reader on the VNET injection Enterprise Policy"
}

resource "azurerm_role_assignment" "enterprise_policy_reader" {
  scope                = azapi_resource.enterprise_policy.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.power_platform_admins.object_id
}

# ─────────────────────────────────────────────────────────────
# Provision the Power Platform environment and link its VNET policy
# ─────────────────────────────────────────────────────────────
resource "powerplatform_environment" "this" {
  display_name     = var.power_platform_environment_name
  location         = var.enterprise_policy_location
  environment_type = "Sandbox"

  dataverse = {
    language_code     = var.dataverse_language_code
    currency_code     = var.dataverse_currency_code
    security_group_id = var.power_platform_environment_security_group_id
  }
}

# VNET support requires a Managed Environment.
resource "powerplatform_managed_environment" "this" {
  environment_id             = powerplatform_environment.this.id
  is_usage_insights_disabled = true
  is_group_sharing_disabled  = false
  limit_sharing_mode         = "ExcludeSharingToSecurityGroups"
  max_limit_user_sharing     = -1
  solution_checker_mode      = "Warn"
  suppress_validation_emails = true
}

resource "powerplatform_enterprise_policy" "environment_link" {
  environment_id = powerplatform_environment.this.id
  policy_type    = "NetworkInjection"
  system_id      = azapi_resource.enterprise_policy.output.properties.systemId

  depends_on = [
    powerplatform_managed_environment.this,
    azurerm_role_assignment.enterprise_policy_reader,
    azurerm_subnet_nat_gateway_association.powerplatform,
    azurerm_nat_gateway_public_ip_association.powerplatform,
    azurerm_private_dns_zone_virtual_network_link.this,
    azurerm_private_dns_zone_virtual_network_link.internal
  ]
}

# ─────────────────────────────────────────────────────────────
# VNET Peering — PP-VNET-VNET-LINK
# Bidirectional peering between primary (East US) and
# secondary (West US) Power Platform VNETs.
# ─────────────────────────────────────────────────────────────
resource "azurerm_virtual_network_peering" "primary_to_secondary" {
  name                         = "PP-VNET-VNET-LINK-primary-to-secondary"
  resource_group_name          = azurerm_resource_group.this["primary"].name
  virtual_network_name         = azurerm_virtual_network.this["primary"].name
  remote_virtual_network_id    = azurerm_virtual_network.this["secondary"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "secondary_to_primary" {
  name                         = "PP-VNET-VNET-LINK-secondary-to-primary"
  resource_group_name          = azurerm_resource_group.this["secondary"].name
  virtual_network_name         = azurerm_virtual_network.this["secondary"].name
  remote_virtual_network_id    = azurerm_virtual_network.this["primary"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ─────────────────────────────────────────────────────────────
# App Service VNET Integration Subnet — primary VNET only
# Dedicated subnet with Microsoft.Web/serverFarms delegation
# required for App Service regional VNET integration.
# ─────────────────────────────────────────────────────────────
resource "azurerm_subnet" "app_service" {
  name                 = "snet-app-service"
  resource_group_name  = azurerm_resource_group.this["primary"].name
  virtual_network_name = azurerm_virtual_network.this["primary"].name
  address_prefixes     = var.app_service_subnet_address_prefix

  delegation {
    name = "app-service-delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "app_service" {
  subnet_id                 = azurerm_subnet.app_service.id
  network_security_group_id = azurerm_network_security_group.powerplatform["primary"].id
}

resource "azurerm_subnet_nat_gateway_association" "app_service" {
  subnet_id      = azurerm_subnet.app_service.id
  nat_gateway_id = azurerm_nat_gateway.powerplatform["primary"].id
}

# ─────────────────────────────────────────────────────────────
# App Service Plan — P0v3 in East US
# Hosts the PowerShell Web App in the shared RG.
# ─────────────────────────────────────────────────────────────
resource "azurerm_service_plan" "this" {
  name                = var.app_service_plan_name
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  os_type             = "Linux"
  sku_name            = "P0v3"
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────
# App Service (Web App) — PowerShell in East US
# VNET-integrated: outbound traffic routes through the primary
# VNET. Private endpoints in both VNETs provide inbound access
# from Power Platform connectors.
# ─────────────────────────────────────────────────────────────
resource "azurerm_linux_web_app" "this" {
  name                = var.app_service_name
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  service_plan_id     = azurerm_service_plan.this.id

  virtual_network_subnet_id = azurerm_subnet.app_service.id

  site_config {
    application_stack {
      node_version = "24-lts"
    }
    vnet_route_all_enabled = true
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────
# Private Endpoints — App Service reachable from both VNETs
# Uses the existing privatelink.azurewebsites.net DNS zone
# so Power Platform connectors resolve the App Service to
# a private IP inside the VNET.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "app" {
  for_each = var.vnets

  name                = "pe-${var.app_service_name}-${each.key}"
  location            = azurerm_resource_group.this[each.key].location
  resource_group_name = azurerm_resource_group.this[each.key].name
  subnet_id           = azurerm_subnet.endpoints[each.key].id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.app_service_name}-${each.key}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }
}

# ─────────────────────────────────────────────────────────────
# Private DNS A Records — App Service
# Explicitly managed to include IPs from BOTH PP VNET endpoints.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_a_record" "app_service" {
  name                = var.app_service_name
  zone_name           = azurerm_private_dns_zone.this["websites"].name
  resource_group_name = azurerm_resource_group.shared.name
  ttl                 = 10
  records             = [for k, pe in azurerm_private_endpoint.app : pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "app_service_scm" {
  name                = "${var.app_service_name}.scm"
  zone_name           = azurerm_private_dns_zone.this["websites"].name
  resource_group_name = azurerm_resource_group.shared.name
  ttl                 = 10
  records             = [for k, pe in azurerm_private_endpoint.app : pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}
