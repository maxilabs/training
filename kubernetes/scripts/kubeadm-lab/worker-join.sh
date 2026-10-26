#!/usr/bin/env bash
# Laat alle workers joinen met een vers token van de control plane. Gebruik: ./worker-join.sh
# Uitleg (wat en waarom): SCRIPTS.md
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# ── 1. Join-commando ophalen ──────────────────────────────────────────────────
# Op cp1 maakt 'kubeadm token create' een nieuw bootstrap-token (tijdelijk geldig).
# '--print-join-command' print meteen het complete commando, bijv.:
#   kubeadm join 192.168.122.11:6443 --token abc.123 --discovery-token-ca-cert-hash sha256:...
# token     = bewijst tegenover de API-server dat de node mag joinen
# CA-hash   = de worker controleert hiermee dat hij met de ECHTE API-server praat
# Een vers token, omdat het token van 'kubeadm init' na 24 uur verloopt.
JOIN="$(vm_ssh "$CP_NODE" 'sudo kubeadm token create --print-join-command')"
[ -n "$JOIN" ] || die "geen join-commando ontvangen"

# ── 2. Elke worker laten joinen ───────────────────────────────────────────────
for n in $(node_names); do
  [ "$n" = "$CP_NODE" ] && continue          # de control plane zelf overslaan
  # kubelet.conf bestaat pas na een geslaagde join -> al gejoind, overslaan.
  if vm_ssh "$n" 'test -f /etc/kubernetes/kubelet.conf'; then log "$n is al gejoind"; continue; fi
  log "join $n"
  # Op de worker: kubeadm haalt de clusterinfo op en de kubelet doet TLS-bootstrap
  # (vraagt met het token een eigen certificaat aan; dat is de CSR in de output).
  vm_ssh "$n" "sudo $JOIN"
done
# Alle nodes horen er nu bij (nog NotReady zolang er geen CNI is).
vm_ssh "$CP_NODE" 'kubectl get nodes -o wide'
