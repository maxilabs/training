#!/usr/bin/env bash
# Draait node-prep.sh op alle nodes (parallel). Gebruik: ./prep-nodes.sh
# Uitleg (wat en waarom): SCRIPTS.md
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# Regels voor /etc/hosts op elke node, bijv. "192.168.122.11 cp1 cp1.lab # kubeadm-lab".
# Het label '# kubeadm-lab' maakt ze later herkenbaar (node-prep.sh vervangt ze netjes).
HOSTS_LINES="$(for l in "${NODES[@]}"; do set -- $l; echo "$2 $1 $1.lab # kubeadm-lab"; done)"

# node-prep.sh staat op aristotle, niet op de node. 'bash -s' leest het script van
# stdin ('<node-prep.sh'), dus SSH stuurt het mee en het draait op de node als root.
# De variabelen ervoor (K8S_MINOR, HOSTS_LINES) geven we zo mee aan dat script.
# '&' = op de achtergrond, zodat alle nodes TEGELIJK worden voorbereid;
# '$!' is het proces-ID daarvan, dat bewaren we in 'pids'.
pids=()
for n in $(node_names); do
  log "node-prep op $n"
  vm_ssh "$n" "sudo K8S_MINOR='$K8S_MINOR' HOSTS_LINES='$HOSTS_LINES' bash -s" <node-prep.sh \
    >"prep-$n.log" 2>&1 & pids+=($!)
done

# Wachten tot alle achtergrondprocessen klaar zijn. Faalt er één, dan noemen we
# het logbestand van die node en stoppen we daarna.
rc=0
for i in "${!pids[@]}"; do wait "${pids[$i]}" || { rc=1; echo "zie prep-$(node_names | sed -n "$((i+1))p").log"; }; done
[ $rc -eq 0 ] || die "node-prep mislukt"
# De laatste regel van elk log is de samenvatting: hostname, kubeadm- en containerd-versie.
for n in $(node_names); do tail -1 "prep-$n.log"; done
