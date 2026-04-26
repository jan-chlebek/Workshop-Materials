subscription_id               = "9c65e913-1198-482f-8bfa-3d666aca72ea"
power_platform_environment_id = "2b22e19d-c16c-e05e-90c2-e6c07b39f514"
internal_domain_name          = "contoso.com" # Replace with your company's internal domain

shared_resource_group = {
  name     = "rg-powerplatform-vnet-shared"
  location = "eastus"
}

vnets = {
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
