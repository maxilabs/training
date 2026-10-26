# Invoer van scenario A. Waarden staan in terraform.tfvars (voorbeeld: terraform.tfvars.example)
# of komen van de workflow via -var.

variable "nodes" {
  description = "De VM's van het Terraform-cluster. Andere namen en IP's dan het script-lab (cp1/w1/w2, .11-.13), zodat beide naast elkaar kunnen bestaan."
  type = map(object({
    ip     = string # vast IP; cloud-init zet het statisch (geen DHCP-reservering nodig)
    mac    = string # vaste MAC, zodat de netwerkkaart in de guest altijd herkend wordt
    vcpu   = number
    memory = number # MiB
  }))
  default = {
    "tf-cp1" = { ip = "192.168.122.21", mac = "52:54:00:6b:00:21", vcpu = 2, memory = 4096 }
    "tf-w1"  = { ip = "192.168.122.22", mac = "52:54:00:6b:00:22", vcpu = 2, memory = 4096 }
    "tf-w2"  = { ip = "192.168.122.23", mac = "52:54:00:6b:00:23", vcpu = 2, memory = 4096 }
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : can(cidrhost("${n.ip}/24", 0))])
    error_message = "Elk ip moet een geldig IPv4-adres zijn."
  }
}

variable "control_plane" {
  description = "Naam van de control-plane-node (moet een sleutel in var.nodes zijn)."
  type        = string
  default     = "tf-cp1"
}

variable "ssh_public_key" {
  description = "Publieke SSH-key die cloud-init in de VM's zet (gebruiker ubuntu). De workflow geeft die van de runner mee."
  type        = string
}

variable "image_url" {
  description = "Ubuntu 24.04 cloud image (zelfde als create-vms.sh)."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "disk_gib" {
  description = "Maximale grootte per VM-disk in GiB (qcow2 groeit pas als hij volloopt)."
  type        = number
  default     = 20
}

variable "pool_path" {
  description = "Map voor de libvirt-opslagpool van dit scenario."
  type        = string
  default     = "/var/lib/libvirt/images/kubeadm-tf"
}

variable "network" {
  description = "Bestaand libvirt-netwerk (NAT, 192.168.122.0/24). Terraform beheert dit netwerk niet, het gebruikt het alleen."
  type        = string
  default     = "default"
}

variable "gateway" {
  description = "Gateway en DNS van het libvirt-netwerk."
  type        = string
  default     = "192.168.122.1"
}
