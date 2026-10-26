#!/usr/bin/env bash
# Wacht tot alle nodes uit lab.env (of LAB_ENV) via SSH bereikbaar zijn en cloud-init klaar is.
# Doet hetzelfde als stap 4 van create-vms.sh; nodig omdat Terraform alleen de VM's maakt.
# Gebruik (vanuit de lab-map):  LAB_ENV=/pad/lab-tf.env ./iac/lab-libvirt/wait-nodes.sh
set -euo pipefail
cd "$(dirname "$0")/../.."; source ./lab.env

for n in $(node_names); do
  log "Wachten op SSH van $n ($(node_ip "$n"))"
  # maximaal 60 x 5 s = 5 minuten; de eerste boot downloadt nog pakketten (qemu-guest-agent)
  for _ in $(seq 1 60); do vm_ssh "$n" true 2>/dev/null && break; sleep 5; done
  # SSH werkt; wacht nu tot cloud-init helemaal klaar is
  vm_ssh "$n" 'cloud-init status --wait >/dev/null; hostname' || die "$n niet bereikbaar"
done
log "Alle nodes klaar: $(node_names | xargs)"
