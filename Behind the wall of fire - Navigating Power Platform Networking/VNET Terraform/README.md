# Power Platform VNET Injection — Terraform Setup

This repository contains two **independent** Terraform projects that together provision a Power Platform environment, its VNET injection policy association, and the Azure networking infrastructure.

The `vnet/` project is the core setup. The `azure-functions/` project is a **sample** set of resources demonstrating how to deploy and integrate services (Function App, Web App) onto the VNET — it can be adapted or replaced with your own workloads.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  vnet/  — Power Platform VNET Infrastructure                        │
│                                                                      │
│  ┌─────────────────────┐       peering       ┌─────────────────────┐│
│  │  Primary VNET        │◄────────────────────►  Secondary VNET     ││
│  │  East US (10.100/16) │                     │  West US (10.200/16)││
│  │  ┌─────────────────┐ │                     │  ┌─────────────────┐││
│  │  │ PP Delegation   │ │                     │  │ PP Delegation   │││
│  │  │ Subnet + NAT GW │ │                     │  │ Subnet + NAT GW │││
│  │  ├─────────────────┤ │                     │  ├─────────────────┤││
│  │  │ Endpoints Subnet│ │                     │  │ Endpoints Subnet│││
│  │  ├─────────────────┤ │                     │  └─────────────────┘││
│  │  │ App Service     │ │                     └─────────────────────┘│
│  │  │ Subnet          │ │                                            │
│  │  └─────────────────┘ │   ┌──────────────────────────────────┐    │
│  └─────────────────────┘   │ Shared RG                         │    │
│                             │  Enterprise Policy (AzAPI)        │    │
│                             │  Private DNS Zones (7 zones)      │    │
│                             │  App Service Plan + Web App       │    │
│                             │  Entra ID Admin Group             │    │
│                             └──────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│  azure-functions/  — App Services (Function App + Web App)           │
│                                                                      │
│  ┌─────────────────────────────┐                                    │
│  │  Dedicated VNET              │    Private Endpoints into         │
│  │  West US 3 (10.10/16)       │    primary + secondary PP VNETs   │
│  │  ┌─────────────────────┐    │    for inbound access from        │
│  │  │ Integration Subnet  │    │    Power Platform connectors      │
│  │  ├─────────────────────┤    │                                    │
│  │  │ Endpoints Subnet    │    │    Function App: PowerShell 7.4   │
│  │  └─────────────────┘    │    Web App:      Node 24 LTS      │
│  └─────────────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Project 1: `vnet/` — Power Platform VNET Infrastructure

Provisions the Azure networking, a Power Platform Sandbox with Dataverse, Managed Environment settings, and the NetworkInjection enterprise policy association.

> **Prerequisites:** Terraform >= 1.5, Azure CLI, a Power Platform administrator account with available Dataverse capacity and appropriate Managed Environment licensing, and permissions to create the Azure resources, Entra security group, and Azure role assignment. Register `Microsoft.PowerPlatform` in the Azure subscription before deployment. The account linking the policy needs read access to it; the sample admin group is created empty, so its Reader assignment alone does not grant the deploying user access.

### Resources Created

| Resource | Description |
|---|---|
| **Resource Groups** (×2 + shared) | One per VNET region + a shared RG for central resources |
| **VNETs** (×2) | Primary (East US `10.100.0.0/16`) and Secondary (West US `10.200.0.0/16`) |
| **Delegated Subnets** (×2) | `Microsoft.PowerPlatform/enterprisePolicies` delegation for VNET injection |
| **Endpoints Subnets** (×2) | Hosts private endpoints for backend services |
| **App Service Subnet** (×1) | Primary VNET only — `Microsoft.Web/serverFarms` delegation |
| **NSGs** (×2) | Allow HTTPS (443) outbound + SQL (1433) outbound |
| **NAT Gateways** (×2) | Static outbound IP per VNET for firewall allow-listing |
| **VNET Peering** | Bidirectional peering between primary ↔ secondary |
| **Private DNS Zones** (×7 + internal) | `privatelink.azurewebsites.net`, `*.core.windows.net`, SQL, Search + company internal domain |
| **Enterprise Policy** (AzAPI) | `NetworkInjection` kind — links both VNETs to Power Platform |
| **Entra ID Security Group** | Power Platform Admins group with Reader role on the Enterprise Policy |
| **Power Platform Environment** | Terraform-managed Sandbox with Dataverse in the policy geography |
| **Managed Environment** | Enables the managed features required for VNET support |
| **Environment Link** | `powerplatform_enterprise_policy` assigns the NetworkInjection policy using its system ID |
| **App Service Plan + Web App** | P0v3 Linux, Node 24 LTS, private endpoints in both VNETs |

### Providers

- `azurerm ~> 4.0` — core Azure resources
- `azapi ~> 2.0` — Enterprise Policy (not in AzureRM)
- `azuread ~> 3.0` — Entra ID security group
- `microsoft/power-platform ~> 4.1` — environment, Managed Environment settings, and policy assignment

### Usage

```bash
az login --tenant YOUR-TENANT-ID
az account set --subscription YOUR-SUBSCRIPTION-ID
cd vnet/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### Input Variables

| Variable | Description |
|---|---|
| `subscription_id` | Azure subscription ID |
| `power_platform_environment_name` | Optional display name; defaults to `Power Platform Networking Workshop` |
| `dataverse_language_code` / `dataverse_currency_code` | Optional Dataverse settings; default to `1033` / `USD` |
| `power_platform_environment_security_group_id` | Optional Entra group for environment access; defaults to the all-zero GUID (no group restriction) |

### Environment provisioning and policy assignment

Terraform creates the Sandbox in `enterprise_policy_location` (`unitedstates` by default), matching the policy geography. If you change the geography, update both VNET regions to a supported pair. The environment uses `dataverse_language_code` and `dataverse_currency_code` for its database.

`powerplatform_enterprise_policy.environment_link` uses `azapi_resource.enterprise_policy.output.properties.systemId`; this is the Power Platform system ID, not the Azure ARM resource ID. The assignment waits for Managed Environment configuration, policy Reader assignment, NAT connectivity, and DNS links.

The Power Platform provider uses the Azure CLI user session (`use_cli = true`). PAC CLI and the Enterprise Policies PowerShell module are not required. Use a user login for this workshop; the provider's environment documentation lists service principal authentication as unsupported for this resource.

For an existing deployment, remove the old `power_platform_environment_id` input. Before applying, import the existing environment into `powerplatform_environment.this` and reconcile its name, type, geography, and Dataverse settings with the configuration to avoid creating a second environment. The policy assignment is now a different Terraform resource from `terraform_data.environment_link`; review the plan and existing association before applying this migration. The new environment is owned by Terraform and is included in `terraform destroy`.

References: [environment resource](https://github.com/microsoft/terraform-provider-power-platform/blob/main/docs/resources/environment.md), [enterprise policy assignment](https://github.com/microsoft/terraform-provider-power-platform/blob/main/docs/resources/enterprise_policy.md), [Azure CLI authentication](https://github.com/microsoft/terraform-provider-power-platform/blob/main/docs/guides/azure_cli.md), and [VNET prerequisites and region mapping](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure).

### Key Outputs

| Output | Description |
|---|---|
| `vnet_ids` | VNET IDs keyed by role (primary/secondary) |
| `subnet_ids` | Delegated subnet IDs keyed by role |
| `endpoints_subnet_ids` | Private endpoints subnet IDs |
| `enterprise_policy_id` | Enterprise Policy ARM resource ID |
| `enterprise_policy_system_id` | Power Platform policy system ID used for the association |
| `power_platform_environment_id` / `power_platform_environment_url` | Created environment GUID and Dataverse URL |
| `nat_gateway_ids` | NAT Gateway IDs keyed by role |

### Files

```
vnet/
├── main.tf                  # All resources (VNETs, subnets, NSGs, NAT GWs, DNS, Enterprise Policy, peering, App Service)
├── variables.tf             # Input variables with defaults
├── outputs.tf               # Exported resource IDs
├── providers.tf             # azurerm + azapi + azuread + powerplatform provider config
└── terraform.tfvars.example # Sample variable values
```

---

## Project 2: `azure-functions/` — Sample App Services (Function App + Web App)

A **sample** set of resources that demonstrates how to deploy services and integrate them onto the Power Platform VNET. Deploys a Function App and Web App in a dedicated VNET (West US 3), with private endpoints reaching back into both Power Platform VNETs. This can serve as a template for integrating your own workloads.

### Resources Created

| Resource | Description |
|---|---|
| **Resource Group** | `rg-powerplatform-appservices-westus3` |
| **Dedicated VNET** | West US 3 (`10.10.0.0/16`) — separate from the PP VNETs |
| **Integration Subnet** | `Microsoft.Web/serverFarms` delegation for outbound VNET integration |
| **Endpoints Subnet** | Hosts private endpoints for storage |
| **Storage Account** | LRS, TLS 1.2, private blob container for deployment packages |
| **App Service Plan** | B1 Linux |
| **Function App** | PowerShell 7.4, private (no public access), VNET-integrated, deployed via `WEBSITE_RUN_FROM_PACKAGE` |
| **Web App** | Node 24 LTS, private (no public access), VNET-integrated |
| **Private Endpoints — Function App** (×2) | One in each PP VNET endpoints subnet (primary + secondary) |
| **Private Endpoints — Web App** (×2) | One in each PP VNET endpoints subnet (primary + secondary) |
| **Private Endpoints — Storage** (×4) | blob, file, table, queue — in the dedicated VNET |
| **Private DNS Zones — Storage** (×4) | `privatelink.{blob,file,table,queue}.core.windows.net` |
| **Private DNS A Records** | Function App + Web App + SCM endpoints in the PP websites DNS zone |

### Providers

- `azurerm ~> 4.0` — core Azure resources
- `archive ~> 2.0` — zip packaging for function deployment

### Prerequisites

The `vnet/` project must be deployed first. This project references existing PP VNET resources via data sources:
- Endpoints subnets in primary and secondary PP VNETs
- `privatelink.azurewebsites.net` DNS zone in the shared RG

### Usage

```bash
cd azure-functions/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### Required Variables

| Variable | Description |
|---|---|
| `subscription_id` | Azure subscription ID |
| `function_app_name` | Globally unique Function App name |
| `app_service_name` | Globally unique App Service name |
| `storage_account_name` | Globally unique storage account name (3-24 lowercase alphanumeric) |
| `pp_vnets` | Map of PP VNET details (resource group, VNET name, endpoints subnet) |
| `pp_shared_resource_group_name` | Shared RG hosting the Private DNS Zones |

### Key Outputs

| Output | Description |
|---|---|
| `function_app_id` | Function App resource ID |
| `function_app_default_hostname` | Function App hostname |
| `app_service_id` | App Service resource ID |
| `app_service_default_hostname` | App Service hostname |

### Included Function Code

A simple healthcheck HTTP trigger (PowerShell) is included and auto-deployed:

```
azure-functions/function-app/
├── host.json                # Functions runtime v2 config
└── healthcheck/
    ├── function.json        # Anonymous GET trigger
    └── run.ps1              # Returns { status: "healthy", timestamp: "..." }
```

### Files

```
azure-functions/
├── main.tf                  # All resources (VNET, storage, App Service Plan, Function App, Web App, PEs, DNS records)
├── variables.tf             # Input variables with defaults
├── outputs.tf               # Exported resource IDs and hostnames
├── providers.tf             # azurerm + archive provider config
├── terraform.tfvars.example # Sample variable values
└── function-app/            # Deployable function code (healthcheck)
```

---

## Deployment Order

1. **`vnet/`** — Deploy the VNET infrastructure first (VNETs, DNS zones, Enterprise Policy, Dataverse Sandbox, Managed Environment settings, environment link)
2. **`azure-functions/`** — Deploy app services second (references existing PP VNET subnets and DNS zones)


