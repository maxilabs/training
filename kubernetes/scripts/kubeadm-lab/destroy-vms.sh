#!/usr/bin/env bash
# Verwijdert alle lab-VM's, hun disks, snapshots en DHCP-reserveringen.
# Uitleg (wat en waarom): SCRIPTS.md
# Gebruik: ./destroy-vms.sh            (vraagt bevestiging)
#          ./destroy-vms.sh --base     (verwijdert ook het base image)
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# Bevestiging vragen: dit is niet terug te draaien. Alleen 'y' gaat door.
read -rp "Alle lab-VM's ($(node_names | xargs)) definitief verwijderen? [y/N] " a
[ "$a" = "y" ] || { echo "Afgebroken."; exit 0; }

for l in "${NODES[@]}"; do
  set -- $l; NAME="$1" IP="$2" MAC="$3"
  if virsh dominfo "$NAME" >/dev/null 2>&1; then
    log "verwijder $NAME"
    # destroy = VM hard uitzetten (stekker eruit); de data blijft nog bestaan.
    virsh destroy "$NAME" >/dev/null 2>&1 || true
    # Interne snapshots moeten eerst weg, anders weigert 'undefine'.
    for s in $(virsh snapshot-list "$NAME" --name 2>/dev/null); do virsh snapshot-delete "$NAME" "$s" >/dev/null; done
    # undefine = VM-definitie weg; --remove-all-storage = ook de qcow2-disk weg.
    virsh undefine "$NAME" --remove-all-storage >/dev/null
  fi
  # De DHCP-reservering uit het libvirt-netwerk halen (tegenhanger van create-vms.sh).
  virsh net-update "$LIBVIRT_NET" delete ip-dhcp-host "<host mac='$MAC' name='$NAME' ip='$IP'/>" --live --config >/dev/null 2>&1 || true
  # Oude SSH-hostkey vergeten; een nieuwe VM op hetzelfde IP heeft een andere key.
  ssh-keygen -f "${HOME}/.ssh/kubeadm-lab_known_hosts" -R "$IP" >/dev/null 2>&1 || true
done
# Met --base ook het gedownloade Ubuntu-image weg (dan downloadt create-vms.sh opnieuw).
[ "${1:-}" = "--base" ] && { log "verwijder base image"; sudo rm -f "$BASE_IMG"; }
log "Opgeruimd."
