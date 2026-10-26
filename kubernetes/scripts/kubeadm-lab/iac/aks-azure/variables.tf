# Invoer van scenario B. Standaardwaarden zijn gekozen voor een klein budget.

variable "resource_group_name" {
  description = "Bestaande resource group (gemaakt door bootstrap.sh). De pipeline-identiteit heeft alleen hier Contributor."
  type        = string
  default     = "rg-k8s-lab"
}

variable "cluster_name" {
  description = "Naam van het AKS-cluster."
  type        = string
  default     = "aks-k8s-lab"
}

variable "kubernetes_version" {
  description = "Kubernetes-versie (bijv. \"1.35\"). null = de aanbevolen versie van AKS op het moment van aanmaken."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM-grootte van de system node pool. AKS eist minimaal 4 vCPU en 4 GB voor system pools; B-series wordt niet ondersteund."
  type        = string
  default     = "Standard_D4as_v5"
}

variable "node_count" {
  description = "Aantal nodes. Microsoft raadt voor productie minimaal 2-3 aan; 1 houdt de kosten in een lab laag."
  type        = number
  default     = 1
}

variable "gitops_repo_url" {
  description = "PUBLIEKE git-repo met de Kubernetes-YAML voor dit cluster (geen secrets erin). Flux haalt hem op."
  type        = string
}

variable "gitops_branch" {
  description = "Branch die Flux volgt."
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Map in de gitops-repo voor dit cluster."
  type        = string
  default     = "./clusters/aks"
}

variable "tags" {
  description = "Tags op alle resources (handig voor kostenoverzicht)."
  type        = map(string)
  default = {
    purpose = "cka-lab"
    owner   = "tobias"
  }
}
