output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.this.id
}

output "vnet_id" {
  description = "ID of the dedicated VNET"
  value       = azurerm_virtual_network.this.id
}

output "integration_subnet_id" {
  description = "ID of the VNet integration subnet"
  value       = azurerm_subnet.integration.id
}

output "endpoints_subnet_id" {
  description = "ID of the endpoints subnet"
  value       = azurerm_subnet.endpoints.id
}

output "function_app_id" {
  description = "Resource ID of the Function App"
  value       = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.this.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.this.default_hostname
}

output "app_service_id" {
  description = "Resource ID of the App Service"
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the App Service"
  value       = azurerm_linux_web_app.this.name
}

output "app_service_default_hostname" {
  description = "Default hostname of the App Service"
  value       = azurerm_linux_web_app.this.default_hostname
}

output "function_app_private_endpoint_ids" {
  description = "IDs of the Function App private endpoints (per PP VNET)"
  value       = { for k, pe in azurerm_private_endpoint.function_app : k => pe.id }
}

output "app_service_private_endpoint_ids" {
  description = "IDs of the App Service private endpoints (per PP VNET)"
  value       = { for k, pe in azurerm_private_endpoint.app_service : k => pe.id }
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.this.id
}

output "storage_private_endpoint_ids" {
  description = "IDs of the Storage private endpoints"
  value       = { for k, v in azurerm_private_endpoint.storage : k => v.id }
}
