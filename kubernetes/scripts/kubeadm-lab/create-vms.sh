#!/usr/bin/env bash
# Maakt de 3 lab-VM's aan op aristotle (libvirt/KVM, Ubuntu 24.04 cloud image + cloud-init).
# Uitleg (wat en waarom): SCRIPTS.md
# Gebruik: ./create-vms.sh

# set -e: stop bij de eerste fout | -u: fout bij een onbekende variabele
# -o pipefail: een pipe faalt als één van de commando's erin faalt
set -euo pipefail
# Naar de map van dit script gaan (dan werkt het vanaf elke plek) en de instellingen laden.
cd "$(dirname "$0")"; source ./lab.env

# ── 1. Voorcontroles ──────────────────────────────────────────────────────────
# Liever meteen een duidelijke fout dan halverwege vastlopen.
# Bestaan alle benodigde programma's?
for b in virsh virt-install qemu-img curl sha256sum; do command -v "$b" >/dev/null || die "$b ontbreekt"; done
# Je publieke SSH-key gaat via cloud-init in de VM, zodat je zonder wachtwoord inlogt.
PUBKEY_FILE="$(ls "${HOME}"/.ssh/*.pub 2>/dev/null | head -1 || true)"
[ -n "$PUBKEY_FILE" ] || die "Geen ~/.ssh/*.pub gevonden. Maak er een met: ssh-keygen -t ed25519"
log "SSH-key: $PUBKEY_FILE"
# Het libvirt-netwerk (virbr0) moet draaien, anders krijgen de VM's geen IP.
virsh net-info "$LIBVIRT_NET" | grep -q 'Active:.*yes' || die "libvirt-netwerk '$LIBVIRT_NET' is niet actief"

# osinfo vertelt libvirt welk OS er draait, zodat het goede standaardinstellingen kiest.
# ubuntu24.04 als de osinfo-db die kent, anders een generieke Linux-waarde.
OSINFO="ubuntu24.04"
command -v osinfo-query >/dev/null && ! osinfo-query os short-id="$OSINFO" | grep -q "$OSINFO" && OSINFO="linux2022"
log "osinfo: $OSINFO"

# ── 2. Base image downloaden en de checksum controleren ───────────────────────
# Alleen als het image er nog niet is (een tweede run downloadt niets).
if ! sudo test -f "$BASE_IMG"; then
  # Tijdelijke map; 'trap ... EXIT' ruimt hem op, ook als het script halverwege stopt.
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  log "Download $IMG_FILE"
  curl -fL --progress-bar -o "$TMP/$IMG_FILE" "$IMG_URL_BASE/$IMG_FILE"
  # SHA256SUMS is Ubuntu's lijst met checksums. sha256sum -c vergelijkt het
  # gedownloade bestand daarmee: beschadigd of gemanipuleerd = stoppen.
  curl -fsSL -o "$TMP/SHA256SUMS" "$IMG_URL_BASE/SHA256SUMS"
  (cd "$TMP" && grep " \*\?${IMG_FILE}\$" SHA256SUMS | sha256sum -c -) || die "checksum klopt niet"
  # Naar de libvirt-imagemap (van root), alleen-lezen voor anderen.
  sudo install -m 0644 "$TMP/$IMG_FILE" "$BASE_IMG"
fi

# ── 3. Per node: vast IP, eigen disk, cloud-init, VM aanmaken ─────────────────
for l in "${NODES[@]}"; do
  # Splits de NODES-regel ("cp1 192.168.122.11 52:54:...") in losse variabelen.
  set -- $l; NAME="$1" IP="$2" MAC="$3" CPU="$4" MEM="$5"
  # Bestaat de VM al? Dan niets doen (het script mag je veilig opnieuw draaien).
  if virsh dominfo "$NAME" >/dev/null 2>&1; then log "$NAME bestaat al, overslaan"; continue; fi

  # DHCP-reservering in libvirt: deze MAC krijgt altijd dit IP.
  # --live = nu meteen, --config = ook na herstart van libvirt. '|| true': bestaat al = prima.
  log "$NAME: vaste IP $IP reserveren"
  virsh net-update "$LIBVIRT_NET" add ip-dhcp-host \
    "<host mac='$MAC' name='$NAME' ip='$IP'/>" --live --config 2>/dev/null || true

  # Overlay-disk: '-b BASE_IMG' = het base image is de onderlaag (alleen-lezen).
  # De VM schrijft alleen zijn eigen wijzigingen in dit bestand. Snel en zuinig.
  DISK="${IMG_DIR}/kubeadm-lab-${NAME}.qcow2"
  sudo qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMG" "$DISK" "$DISK_SIZE"

  # cloud-init: instructies die de VM bij de EERSTE boot uitvoert.
  # user-data hieronder: hostname zetten, gebruiker 'ubuntu' met jouw SSH-key en
  # sudo zonder wachtwoord, en qemu-guest-agent (laat libvirt met de VM praten).
  CI="$(mktemp -d)"
  cat >"$CI/user-data" <<EOF
#cloud-config
hostname: $NAME
fqdn: $NAME.lab
manage_etc_hosts: false
users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$PUBKEY_FILE")
packages: [qemu-guest-agent]
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
EOF
  # meta-data: de 'identiteit' van de instance; cloud-init draait één keer per instance-id.
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$NAME" "$NAME" >"$CI/meta-data"

  # virt-install maakt en start de VM:
  #   --cpu host-passthrough  VM ziet de echte CPU-features van de host (sneller)
  #   --import                niet installeren, gewoon booten van de bestaande disk
  #   bus=virtio / model=virtio  snelle gevirtualiseerde disk en netwerkkaart
  #   --cloud-init            libvirt maakt van user-data/meta-data een ISO als cdrom
  #   --graphics none --noautoconsole  geen scherm, niet wachten: het script gaat door
  log "$NAME: VM aanmaken ($CPU vCPU, $MEM MiB)"
  virt-install --name "$NAME" --memory "$MEM" --vcpus "$CPU" --cpu host-passthrough \
    --osinfo "$OSINFO" --import \
    --disk path="$DISK",format=qcow2,bus=virtio \
    --network network="$LIBVIRT_NET",mac="$MAC",model=virtio \
    --cloud-init user-data="$CI/user-data",meta-data="$CI/meta-data" \
    --graphics none --noautoconsole
  rm -rf "$CI"
done

# ── 4. Wachten tot de VM's klaar zijn ─────────────────────────────────────────
for n in $(node_names); do
  log "Wachten op SSH van $n ($(node_ip "$n"))"
  # Maximaal 60 x 5 s = 5 minuten proberen of SSH al werkt.
  for _ in $(seq 1 60); do vm_ssh "$n" true 2>/dev/null && break; sleep 5; done
  # SSH werkt, maar cloud-init kan nog bezig zijn (pakketten). '--wait' wacht tot het klaar is.
  vm_ssh "$n" 'cloud-init status --wait >/dev/null; hostname' || die "$n niet bereikbaar"
done
log "Klaar. VM's: $(node_names | xargs)"
