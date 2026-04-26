# ─────────────────────────────────────────────────────────────
# App Services (P1v3) with dedicated VNET — West US 3
#
# This config creates:
#   1. Resource Group
#   2. Dedicated VNET with integration + endpoints subnets
#   3. Private DNS zones for storage (linked to VNET)
#   4. Storage Account with deployment blob container
#   5. App Service Plan (P1v3 — Linux)
#   6. Linux Function App (PowerShell 7.4, private, VNet integrated)
#   7. Linux Web App (Node 20, private, VNet integrated)
#   8. 4x Private Endpoints for Storage in dedicated VNET
#   9. Private Endpoints for Function App in both Power Platform VNETs
#  10. Private Endpoints for App Service in both Power Platform VNETs
#  11. Healthcheck function deployment package
#
# Relies on existing Power Platform VNET infrastructure:
#   - PP VNET endpoints subnets (primary + secondary), PP websites private DNS zone
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# Data: existing Power Platform VNET infrastructure
# ─────────────────────────────────────────────────────────────
data "azurerm_subnet" "pp_endpoints" {
  for_each = var.pp_vnets

  name                 = each.value.endpoints_subnet_name
  virtual_network_name = each.value.vnet_name
  resource_group_name  = each.value.resource_group_name
}

data "azurerm_private_dns_zone" "pp_websites" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = var.pp_shared_resource_group_name
}

# ─────────────────────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ─────────────────────────────────────────────────────────────
# Dedicated VNET
# ─────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Integration subnet — delegated to Microsoft.Web/serverFarms
# Used by Function App and App Service for outbound VNet integration.
resource "azurerm_subnet" "integration" {
  name                 = var.integration_subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.integration_subnet_address_prefix

  delegation {
    name = "webapp-delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

# Endpoints subnet — hosts private endpoints for storage
resource "azurerm_subnet" "endpoints" {
  name                 = var.endpoints_subnet_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.endpoints_subnet_address_prefix

  private_endpoint_network_policies = "Disabled"
}

# ─────────────────────────────────────────────────────────────
# Private DNS Zones for Storage
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "storage" {
  for_each = toset(["file", "table", "blob", "queue"])

  name                = "privatelink.${each.key}.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  for_each = toset(["file", "table", "blob", "queue"])

  name                  = "${var.vnet_name}-${each.key}-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

# ─────────────────────────────────────────────────────────────
# Storage Account
# ─────────────────────────────────────────────────────────────
resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  tags                            = var.tags
}

# Blob container for function deployment artifacts
resource "azurerm_storage_container" "deployment" {
  name                  = var.storage_blob_container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# ─────────────────────────────────────────────────────────────
# App Service Plan — B1 (Linux)
# Basic compute with VNet integration support.
# ─────────────────────────────────────────────────────────────
resource "azurerm_service_plan" "this" {
  name                = var.hosting_plan_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────
# Function App — Linux, PowerShell 7.4, P1v3
# Public access disabled — reachable only via Private Endpoint.
# VNet integration routes outbound traffic through the VNET.
# ─────────────────────────────────────────────────────────────
resource "azurerm_linux_function_app" "this" {
  name                = var.function_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key

  virtual_network_subnet_id = azurerm_subnet.integration.id

  public_network_access_enabled                = false
  https_only                                   = true
  ftp_publish_basic_authentication_enabled     = false
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    vnet_route_all_enabled = true

    application_stack {
      powershell_core_version = "7.4"
    }

    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }

  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE = "https://${azurerm_storage_account.this.name}.blob.core.windows.net/${var.storage_blob_container_name}/${azurerm_storage_blob.function_app_package.name}${data.azurerm_storage_account_blob_container_sas.deploy.sas}"
  }

  tags = var.tags

  depends_on = [azurerm_storage_container.deployment]
}

# ─────────────────────────────────────────────────────────────
# App Service — Linux, Node 20
# Public access disabled — reachable only via Private Endpoint.
# VNet integration routes outbound traffic through the VNET.
# ─────────────────────────────────────────────────────────────
resource "azurerm_linux_web_app" "this" {
  name                = var.app_service_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  virtual_network_subnet_id = azurerm_subnet.integration.id

  public_network_access_enabled                = false
  https_only                                   = true
  ftp_publish_basic_authentication_enabled     = false
  webdeploy_publish_basic_authentication_enabled = false

  site_config {
    vnet_route_all_enabled = true

    application_stack {
      node_version = "24-lts"
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────
# Private Endpoints — Function App in Power Platform VNETs
# Allows Power Platform connectors to call the Function App
# from both primary (eastus) and secondary (westus) VNETs.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "function_app" {
  for_each = var.pp_vnets

  name                = "pe-${var.function_app_name}-${each.key}"
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  subnet_id           = data.azurerm_subnet.pp_endpoints[each.key].id
  tags                = var.tags

  private_service_connection {
    name                           = "pe-${var.function_app_name}-${each.key}"
    private_connection_resource_id = azurerm_linux_function_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }
}

# ─────────────────────────────────────────────────────────────
# Private Endpoints — App Service in Power Platform VNETs
# Allows Power Platform connectors to call the App Service
# from both primary (eastus) and secondary (westus) VNETs.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "app_service" {
  for_each = var.pp_vnets

  name                = "pe-${var.app_service_name}-${each.key}"
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  subnet_id           = data.azurerm_subnet.pp_endpoints[each.key].id
  tags                = var.tags

  private_service_connection {
    name                           = "pe-${var.app_service_name}-${each.key}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }
}

# ─────────────────────────────────────────────────────────────
# Private DNS A Records — Function App + App Service
# Explicitly managed to include IPs from BOTH PP VNET endpoints.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_dns_a_record" "function_app" {
  name                = var.function_app_name
  zone_name           = data.azurerm_private_dns_zone.pp_websites.name
  resource_group_name = var.pp_shared_resource_group_name
  ttl                 = 10
  records             = [for k, pe in azurerm_private_endpoint.function_app : pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "function_app_scm" {
  name                = "${var.function_app_name}.scm"
  zone_name           = data.azurerm_private_dns_zone.pp_websites.name
  resource_group_name = var.pp_shared_resource_group_name
  ttl                 = 10
  records             = [for k, pe in azurerm_private_endpoint.function_app : pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "app_service" {
  name                = var.app_service_name
  zone_name           = data.azurerm_private_dns_zone.pp_websites.name
  resource_group_name = var.pp_shared_resource_group_name
  ttl                 = 10
  records             = [for k, pe in azurerm_private_endpoint.app_service : pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "app_service_scm" {
  name                = "${var.app_service_name}.scm"
  zone_name           = data.azurerm_private_dns_zone.pp_websites.name
  resource_group_name = var.pp_shared_resource_group_name
  ttl                 = 10
  records             = [for k, pe in azurerm_private_endpoint.app_service : pe.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────
# Private Endpoints for Storage (in dedicated VNET)
# Ensures storage traffic stays private within the VNET.
# ─────────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "storage" {
  for_each = toset(["file", "table", "blob", "queue"])

  name                = "pe-${var.storage_account_name}-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "${each.key}PrivateLinkConnection"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "${var.storage_account_name}-${each.key}-endpoint"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage[each.key].id]
  }
}

# ─────────────────────────────────────────────────────────────
# Function App Code — Healthcheck HTTP trigger
# Packages the function-app/ directory and uploads to the
# deployment blob container via WEBSITE_RUN_FROM_PACKAGE.
# ─────────────────────────────────────────────────────────────
data "archive_file" "function_app" {
  type        = "zip"
  source_dir  = "${path.module}/function-app"
  output_path = "${path.module}/.terraform/tmp/function-app.zip"
}

resource "azurerm_storage_blob" "function_app_package" {
  name                   = "function-app.zip"
  storage_account_name   = azurerm_storage_account.this.name
  storage_container_name = azurerm_storage_container.deployment.name
  type                   = "Block"
  source                 = data.archive_file.function_app.output_path
  content_md5            = data.archive_file.function_app.output_md5
}

# SAS token for the function deployment blob container
# Adjust start/expiry dates as needed for your workshop timeline.
data "azurerm_storage_account_blob_container_sas" "deploy" {
  connection_string = azurerm_storage_account.this.primary_connection_string
  container_name    = azurerm_storage_container.deployment.name
  https_only        = true
  start             = "2026-04-01"
  expiry            = "2027-04-01"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}
