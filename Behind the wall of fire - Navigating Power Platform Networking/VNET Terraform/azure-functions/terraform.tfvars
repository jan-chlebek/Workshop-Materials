subscription_id               = "" # To be provided
location                      = "westus3"
resource_group_name           = "rg-powerplatform-appservices-westus3"
function_app_name             = "func-pp-vnet-workshop-westus3"
app_service_name              = "app-pp-vnet-workshop-westus3"
storage_account_name          = "stppvnetworkshopwus3"
hosting_plan_name             = "asp-pp-vnet-workshop-westus3"
vnet_name                     = "vnet-appservices-westus3"

# Based on VNET config
pp_vnets = { 
  primary = {
    location              = "eastus"
    resource_group_name   = "rg-powerplatform-vnet-primary-eastus"
    vnet_name             = "vnet-powerplatform-primary-eastus"
    endpoints_subnet_name = "snet-endpoints"
  }
  secondary = {
    location              = "westus"
    resource_group_name   = "rg-powerplatform-vnet-secondary-westus"
    vnet_name             = "vnet-powerplatform-secondary-westus"
    endpoints_subnet_name = "snet-endpoints"
  }
}
pp_shared_resource_group_name = "rg-powerplatform-vnet-shared"
