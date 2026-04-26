variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "vnets" {
  description = "Map of VNET configurations keyed by role (primary, secondary). Each VNET gets its own RG, DNS zones, NAT gateway, and enterprise policy."
  type = map(object({
    location                        = string
    resource_group_name             = string
    vnet_name                       = string
    vnet_address_space              = list(string)
    subnet_name                     = string
    subnet_address_prefix           = list(string)
    endpoints_subnet_name           = string
    endpoints_subnet_address_prefix = list(string)
  }))

  default = {
    primary = {
      location                        = "eastus"
      resource_group_name             = "rg-powerplatform-vnet-primary-eastus"
      vnet_name                       = "vnet-powerplatform-primary-eastus"
      vnet_address_space              = ["10.100.0.0/16"]
      subnet_name                     = "snet-powerplatform-delegation"
      subnet_address_prefix           = ["10.100.0.0/19"]
      endpoints_subnet_name           = "snet-endpoints"
      endpoints_subnet_address_prefix = ["10.100.32.0/19"]
    }
    secondary = {
      location                        = "westus"
      resource_group_name             = "rg-powerplatform-vnet-secondary-westus"
      vnet_name                       = "vnet-powerplatform-secondary-westus"
      vnet_address_space              = ["10.200.0.0/16"]
      subnet_name                     = "snet-powerplatform-delegation"
      subnet_address_prefix           = ["10.200.0.0/19"]
      endpoints_subnet_name           = "snet-endpoints"
      endpoints_subnet_address_prefix = ["10.200.32.0/19"]
    }
  }
}

variable "shared_resource_group" {
  description = "Shared resource group that hosts the Enterprise Policy and Private DNS Zones"
  type = object({
    name     = string
    location = string
  })
  default = {
    name     = "rg-powerplatform-shared"
    location = "eastus"
  }
}

variable "enterprise_policy_name" {
  description = "Name of the single Power Platform Enterprise Policy connected to both VNETs"
  type        = string
  default     = "ep-vnet-injection"
}

variable "power_platform_admin_group_name" {
  description = "Display name of the Entra ID security group for Power Platform Admins. The Enterprise Policy is shared with this group."
  type        = string
  default     = "SG-PowerPlatform-VNET-Admins"
}

variable "enterprise_policy_location" {
  description = "Power Platform region for the Enterprise Policy (e.g. 'unitedstates', 'europe', 'uk'). This is NOT an Azure region."
  type        = string
  default     = "unitedstates"
}

variable "power_platform_environment_id" {
  description = "The Power Platform environment ID to link (GUID format, e.g. '7ce30fc7-b70d-e1c5-beaa-15b668236810')"
  type        = string
}

variable "internal_domain_name" {
  description = "Company internal domain name for Private DNS Zone (e.g. 'contoso.com'). Replace with your organisation's internal domain."
  type        = string
  default     = "contoso.com"
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan (B1 — cheapest VNET-integrated SKU)"
  type        = string
  default     = "asp-powerplatform-shared"
}

variable "app_service_name" {
  description = "Name of the PowerShell App Service (Web App)"
  type        = string
  default     = "app-powerplatform-shared"
}

variable "app_service_subnet_address_prefix" {
  description = "Address prefix for the App Service VNET integration subnet in the primary VNET"
  type        = list(string)
  default     = ["10.100.64.0/24"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Workshop"
    Purpose     = "PowerPlatform-VNET-Injection"
    ManagedBy   = "Terraform"
  }
}
