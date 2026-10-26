# Uitvoer na 'terraform apply'.

output "get_credentials" {
  description = "Commando om kubectl met dit cluster te laten praten."
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.lab.name} --name ${azurerm_kubernetes_cluster.lab.name}"
}

output "oidc_issuer_url" {
  description = "OIDC-issuer van het cluster; nodig als je een federated credential voor Workload Identity maakt (bijv. voor ESO)."
  value       = azurerm_kubernetes_cluster.lab.oidc_issuer_url
}

output "node_resource_group" {
  description = "De resource group die AKS zelf beheert (VM scale set, load balancer, disks). Niet met de hand wijzigen."
  value       = azurerm_kubernetes_cluster.lab.node_resource_group
}
