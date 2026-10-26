# Scenario A — wat create-vms.sh met virsh/virt-install doet, maar dan declaratief.
# Verschil met het script: Terraform onthoudt in de state wat het gemaakt heeft. 'terraform plan' laat
# zien wat er zou veranderen, 'apply' voert het uit, 'destroy' ruimt precies dit weer op.

# ── 1. Opslagpool ──────────────────────────────────────────────────────────────
# Een eigen map, zodat dit scenario niet in de weg zit van de disks van het script-lab.
resource "libvirt_pool" "lab" {
  name = "kubeadm-tf"
  type = "dir"
  target = {
    path = var.pool_path
  }
  create = {
    build     = true # map aanmaken
    start     = true
    autostart = true
  }
  destroy = {
    delete = true # bij 'terraform destroy' de map ook weghalen
  }
}

# ── 2. Base image: één keer downloaden ─────────────────────────────────────────
# 0.9-schema: downloaden gaat via create.content.url, het formaat via target.format.
# Let op: anders dan create-vms.sh controleert dit GEEN SHA256-checksum.
resource "libvirt_volume" "base" {
  name = "noble-base.qcow2"
  pool = libvirt_pool.lab.name
  target = {
    format = { type = "qcow2" }
  }
  create = {
    content = { url = var.image_url }
  }
}

# ── 3. Per node een overlay-disk op het base image ─────────────────────────────
# backing_store = de onderlaag (alleen-lezen); de VM schrijft alleen zijn eigen wijzigingen.
resource "libvirt_volume" "disk" {
  for_each = var.nodes

  name          = "${each.key}.qcow2"
  pool          = libvirt_pool.lab.name
  capacity      = var.disk_gib
  capacity_unit = "GiB"
  target = {
    format = { type = "qcow2" }
  }
  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }
}

# ── 4. Per node cloud-init (hostname, gebruiker, SSH-key, statisch IP) ─────────
# libvirt_cloudinit_disk maakt lokaal een ISO; die wordt daarna als volume in de pool gezet.
resource "libvirt_cloudinit_disk" "init" {
  for_each = var.nodes

  name = "${each.key}-init"
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname       = each.key
    ssh_public_key = trimspace(var.ssh_public_key)
  })
  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })
  # Netplan v2: vast IP op de NIC met deze MAC. Zo is er geen DHCP-reservering nodig
  # (het script-lab doet dat met 'virsh net-update').
  network_config = yamlencode({
    version = 2
    ethernets = {
      lan = {
        match       = { macaddress = each.value.mac }
        addresses   = ["${each.value.ip}/24"]
        routes      = [{ to = "default", via = var.gateway }]
        nameservers = { addresses = [var.gateway] }
      }
    }
  })
}

resource "libvirt_volume" "init" {
  for_each = var.nodes

  name = "${each.key}-init.iso"
  pool = libvirt_pool.lab.name
  target = {
    format = { type = "raw" }
  }
  create = {
    content = { url = libvirt_cloudinit_disk.init[each.key].path }
  }
}

# ── 5. De VM's ─────────────────────────────────────────────────────────────────
resource "libvirt_domain" "node" {
  for_each = var.nodes

  name        = each.key
  type        = "kvm"
  vcpu        = each.value.vcpu
  memory      = each.value.memory
  memory_unit = "MiB"
  running     = true  # na aanmaken starten
  autostart   = false # niet automatisch starten als aristotle opstart

  cpu = {
    mode = "host-passthrough" # VM ziet de echte CPU-features (zoals --cpu host-passthrough in create-vms.sh)
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    disks = [
      {
        # de systeemdisk (overlay)
        source = { volume = { pool = libvirt_pool.lab.name, volume = libvirt_volume.disk[each.key].name } }
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
      },
      {
        # de cloud-init-ISO als cdrom; cloud-init leest hem bij de eerste boot
        device    = "cdrom"
        read_only = true
        source    = { volume = { pool = libvirt_pool.lab.name, volume = libvirt_volume.init[each.key].name } }
        target    = { dev = "sda", bus = "sata" }
        driver    = { name = "qemu", type = "raw" }
      },
    ]

    interfaces = [
      {
        model  = { type = "virtio" }
        mac    = { address = each.value.mac }
        source = { network = { network = var.network } }
      },
    ]

    # seriële console: 'virsh console tf-cp1' werkt dan, net als bij het script-lab
    consoles = [
      { target = { type = "serial", port = 0 } },
    ]
  }
}
