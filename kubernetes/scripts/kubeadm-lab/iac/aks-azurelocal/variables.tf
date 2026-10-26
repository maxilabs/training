# Invoer van scenario C. De eerste vier krijg je van de beheerder van het Azure Local-cluster.

variable "resource_group_name" {
  description = "Resource group waarin het AKS Arc-cluster komt (meestal dezelfde als die van Azure Local)."
  type        = string
}

variable "custom_location_name" {
  description = "Naam van de custom location van het Azure Local-cluster (aangemaakt bij de Azure Local-deployment)."
  type        = string
}

variable "logical_network_name" {
  description = "Naam van het Azure Local logical network waar de cluster-VM's hun IP uit krijgen."
  type        = string
}

variable "admin_group_object_ids" {
  description = "Object-ID's van Entra-groepen die cluster-admin worden."
  type        = list(string)
}

variable "location" {
  description = "Azure-regio waarin Azure Local geregistreerd is (bijv. westeurope)."
  type        = string
}

variable "cluster_name" {
  description = "Naam van het AKS Arc-cluster."
  type        = string
  default     = "aksarc-k8s-lab"
}

variable "control_plane_ip" {
  description = "Vast IP voor de API-server van het cluster, uit het logical network, buiten de IP-pool. Vraag dit na bij de netwerkbeheerder."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Publieke SSH-key voor toegang tot de node-VM's. null = de module maakt zelf een sleutelpaar."
  type        = string
  default     = null
}
