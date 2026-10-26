# Scenario C — AKS Arc op Azure Local. Laag 1 en 2 doet Azure (via Arc), Terraform vraagt erom.
#
#   Azure Local (je eigen hardware)  ──Arc──▶  Azure Resource Manager
#        └─ custom location + logical network       └─ Terraform/AVM maakt hier het cluster-object
#   De control-plane- en node-VM's draaien op Azure Local; je beheert ze via Azure (portal, az, Terraform).

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Custom location en logical network zijn Azure-resources die de Azure Local-deployment heeft gemaakt.
# azapi leest ze op naam; we hebben alleen hun ID nodig.
data "azapi_resource" "custom_location" {
  type      = "Microsoft.ExtendedLocation/customLocations@2021-08-15"
  name      = var.custom_location_name
  parent_id = data.azurerm_resource_group.rg.id
}

data "azapi_resource" "logical_network" {
  type      = "Microsoft.AzureStackHCI/logicalNetworks@2023-09-01-preview"
  name      = var.logical_network_name
  parent_id = data.azurerm_resource_group.rg.id
}

# De Azure Verified Module maakt: een Arc-connected cluster (Microsoft.Kubernetes/connectedClusters) en
# daarop de AKS Arc-clusterinstantie (Microsoft.HybridContainerService/provisionedClusterInstances).
module "aks_arc" {
  source  = "Azure/avm-res-hybridcontainerservice-provisionedclusterinstance/azurerm"
  version = "2.0.4"

  name               = var.cluster_name
  location           = var.location
  resource_group_id  = data.azurerm_resource_group.rg.id
  custom_location_id = data.azapi_resource.custom_location.id
  logical_network_id = data.azapi_resource.logical_network.id

  control_plane_count = 1 # lab; productie: 3 (HA, zie CONCEPTS.md#ha-control-plane)
  control_plane_ip    = var.control_plane_ip

  # Node pool(s). Autoscaling ondersteunt de module (nog) niet.
  agent_pool_profiles = [
    { name = "nodepool1", count = 1, osType = "Linux" },
  ]

  ssh_public_key              = var.ssh_public_key
  rbac_admin_group_object_ids = var.admin_group_object_ids
  enable_azure_rbac           = false
  enable_oidc_issuer          = true # voor Workload Identity, net als in scenario B
  enable_workload_identity    = true
}
