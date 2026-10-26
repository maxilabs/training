# Scenario B — laag 1 (infrastructuur) en laag 2 (bootstrap) in Terraform; laag 3-4 doet Flux vanuit git.
#
#   Terraform:  resource group (bestaat al) → AKS-cluster → Flux-extensie → Flux-configuratie
#   Flux:       haalt gitops_repo_url/gitops_path op en houdt het cluster daaraan gelijk

# ── De resource group ──────────────────────────────────────────────────────────
# Bewust een data source (lezen) en geen resource (maken): bootstrap.sh maakt hem, en de pipeline krijgt
# alleen rechten OP deze resource group. Zo kan de pipeline niets buiten deze groep aanraken.
data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

# ── Het AKS-cluster ────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "lab" {
  name                = var.cluster_name
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Free = geen SLA en geen kosten voor de control plane; je betaalt alleen de nodes.
  sku_tier = "Free"

  # Automatisch patch-versies en node-images bijwerken (vergelijk: kubeadm upgrade doe je zelf).
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Voor Workload Identity: het cluster geeft ServiceAccount-tokens uit die Entra vertrouwt
  # (zelfde mechanisme als GitHub → Azure, zie CONCEPTS.md#oidc-federatie).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.node_count
    os_sku                      = "Ubuntu"
    temporary_name_for_rotation = "systemtmp" # nodig om later de VM-grootte te kunnen wijzigen
  }

  # De identiteit van het cluster zelf (om bijv. load balancers en disks te maken).
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI in overlay-modus met Cilium als dataplane: Pods krijgen IP's uit een overlay-range
  # (niet uit je VNet), en Cilium dwingt NetworkPolicies af. Zelfde Cilium als ronde C in je lab.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
  }

  tags = var.tags
}

# ── Flux als AKS-extensie ──────────────────────────────────────────────────────
# Azure installeert en onderhoudt Flux in het cluster (namespace flux-system).
# Vereist dat resource provider Microsoft.KubernetesConfiguration geregistreerd is (bootstrap.sh).
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.lab.id
  extension_type = "microsoft.flux"
}

# ── Flux-configuratie: welke repo, welke map ───────────────────────────────────
# Dit maakt in het cluster een GitRepository- en een Kustomization-CR (zie CONCEPTS.md#flux).
# Vanaf hier is het GitOps (pull): wijzigingen in de gitops-repo komen vanzelf in het cluster,
# zonder dat deze pipeline opnieuw draait.
resource "azurerm_kubernetes_flux_configuration" "lab" {
  name       = "lab"
  cluster_id = azurerm_kubernetes_cluster.lab.id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url                      = var.gitops_repo_url
    reference_type           = "branch"
    reference_value          = var.gitops_branch
    sync_interval_in_seconds = 120
  }

  kustomizations {
    name                       = "cluster"
    path                       = var.gitops_path
    sync_interval_in_seconds   = 120
    garbage_collection_enabled = true # 'prune': wat uit git verdwijnt, verdwijnt uit het cluster
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}
