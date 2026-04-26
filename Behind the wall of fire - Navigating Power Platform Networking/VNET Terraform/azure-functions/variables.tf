variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "westus3"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-powerplatform-appservices-westus3"
}

variable "function_app_name" {
  description = "Name of the Azure Function App (must be globally unique)"
  type        = string
}

variable "app_service_name" {
  description = "Name of the App Service (must be globally unique)"
  type        = string
}

variable "hosting_plan_name" {
  description = "Name of the App Service Plan"
  type        = string
  default     = "asp-pp-vnet-workshop-westus3"
}

variable "storage_account_name" {
  description = "Name of the Storage Account (must be globally unique, 3-24 lowercase alphanumeric)"
  type        = string
}

variable "storage_blob_container_name" {
  description = "Name of the blob container for function deployment artifacts"
  type        = string
  default     = "app-package-container"
}

# ─────────────────────────────────────────────────────────────
# Dedicated VNET
# ─────────────────────────────────────────────────────────────
variable "vnet_name" {
  description = "Name of the dedicated VNET"
  type        = string
  default     = "vnet-appservices-westus3"
}

variable "vnet_address_space" {
  description = "Address space for the dedicated VNET"
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "integration_subnet_name" {
  description = "Name of the subnet for VNet integration (outbound)"
  type        = string
  default     = "snet-integration"
}

variable "integration_subnet_address_prefix" {
  description = "Address prefix for the integration subnet"
  type        = list(string)
  default     = ["10.10.0.0/24"]
}

variable "endpoints_subnet_name" {
  description = "Name of the private endpoints subnet"
  type        = string
  default     = "snet-endpoints"
}

variable "endpoints_subnet_address_prefix" {
  description = "Address prefix for the endpoints subnet"
  type        = list(string)
  default     = ["10.10.1.0/24"]
}

# ─────────────────────────────────────────────────────────────
# References to existing Power Platform VNETs (primary + secondary)
# ─────────────────────────────────────────────────────────────
variable "pp_vnets" {
  description = "Map of Power Platform VNETs keyed by role (primary, secondary). PEs are created in each."
  type = map(object({
    location              = string
    resource_group_name   = string
    vnet_name             = string
    endpoints_subnet_name = string
  }))
}

variable "pp_shared_resource_group_name" {
  description = "Shared resource group hosting the Private DNS Zones"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Workshop"
    Purpose     = "PowerPlatform-VNET-AppServices"
    ManagedBy   = "Terraform"
  }
}
