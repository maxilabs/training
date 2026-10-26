# Scenario A — on-prem lab: de VM's van een TWEEDE kubeadm-cluster (tf-cp1, tf-w1, tf-w2) als code.
# Uitleg: CONCEPTS.md#terraform en STUDIEPLAN.md, blok 8.
#
# Provider: dmacvicar/libvirt 0.9.x. Let op: vanaf 0.9.0 is dit een COMPLETE HERSCHRIJVING met een nieuw
# schema dat de libvirt-XML volgt. Voorbeelden van internet voor 0.8.x (network_interface, source = url,
# cloudinit = ...) werken hier niet meer.

terraform {
  required_version = ">= 1.10"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.9" # 0.9.x, niet automatisch naar 0.10 (kan weer breken)
    }
  }

  # State lokaal, maar BUITEN de repo-map: actions/checkout ruimt bij elke run ongetrackte bestanden op,
  # en dan zou je state (en daarmee de kennis welke VM's bij Terraform horen) weg zijn.
  # Het pad geef je mee bij init:  terraform init -backend-config="path=$HOME/.local/state/kubeadm-lab-tf/terraform.tfstate"
  backend "local" {}
}

# qemu:///system = de systeem-libvirt op aristotle (dezelfde als virsh en de lab-scripts gebruiken).
# De gebruiker die Terraform draait (jij of de GitHub-runner) moet in de groep 'libvirt' zitten.
provider "libvirt" {
  uri = "qemu:///system"
}
