output "resource_group_ids" {
  description = "Resource Group IDs keyed by role (primary/secondary)"
  value       = { for k, v in azurerm_resource_group.this : k => v.id }
}

output "shared_resource_group_id" {
  description = "Shared Resource Group ID (Enterprise Policy & DNS Zones)"
  value       = azurerm_resource_group.shared.id
}

output "vnet_ids" {
  description = "Virtual Network IDs keyed by role"
  value       = { for k, v in azurerm_virtual_network.this : k => v.id }
}

output "subnet_ids" {
  description = "Delegated subnet IDs keyed by role"
  value       = { for k, v in azurerm_subnet.powerplatform : k => v.id }
}

output "endpoints_subnet_ids" {
  description = "Private endpoints subnet IDs keyed by role"
  value       = { for k, v in azurerm_subnet.endpoints : k => v.id }
}

output "enterprise_policy_id" {
  description = "Power Platform Enterprise Policy ID"
  value       = azapi_resource.enterprise_policy.id
}

output "enterprise_policy_system_id" {
  description = "Enterprise Policy system ID used for the Power Platform environment association"
  value       = azapi_resource.enterprise_policy.output.properties.systemId
}

output "power_platform_environment_id" {
  description = "GUID of the Power Platform environment managed by Terraform"
  value       = powerplatform_environment.this.id
}

output "power_platform_environment_url" {
  description = "Dataverse URL of the Power Platform environment"
  value       = powerplatform_environment.this.dataverse.url
}

output "enterprise_policy_identity" {
  description = "System-assigned managed identity of the Enterprise Policy"
  value       = azapi_resource.enterprise_policy.identity
}

output "power_platform_admin_group_id" {
  description = "Object ID of the Power Platform Admin security group"
  value       = azuread_group.power_platform_admins.object_id
}

output "nsg_ids" {
  description = "Network Security Group IDs keyed by role"
  value       = { for k, v in azurerm_network_security_group.powerplatform : k => v.id }
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs keyed by role"
  value       = { for k, v in azurerm_nat_gateway.powerplatform : k => v.id }
}

output "nat_gateway_public_ips" {
  description = "Public IP addresses of the NAT Gateways keyed by role"
  value       = { for k, v in azurerm_public_ip.nat : k => v.ip_address }
}

output "dns_zone_ids" {
  description = "Private DNS Zone IDs keyed by zone type (e.g. websites, sql, blob)"
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}

output "internal_dns_zone_id" {
  description = "Private DNS Zone ID for the company internal domain"
  value       = azurerm_private_dns_zone.internal.id
}

output "app_service_plan_id" {
  description = "App Service Plan ID"
  value       = azurerm_service_plan.this.id
}

output "app_service_id" {
  description = "PowerShell App Service (Web App) ID"
  value       = azurerm_linux_web_app.this.id
}

output "app_service_default_hostname" {
  description = "Default hostname of the PowerShell App Service"
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_service_private_endpoint_ips" {
  description = "Private endpoint IP addresses for the App Service keyed by VNET role"
  value       = { for k, v in azurerm_private_endpoint.app : k => v.private_service_connection[0].private_ip_address }
}

