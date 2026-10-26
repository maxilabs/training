#!/usr/bin/env bash
# Fase 1 in één keer: VM's -> node-prep -> kubeadm init -> join -> snapshot 'no-cni'.
# Uitleg (wat en waarom): SCRIPTS.md
# Gebruik: ./bootstrap.sh
set -euo pipefail            # mislukt één stap, dan stopt alles (geen half cluster)
cd "$(dirname "$0")"; source ./lab.env

# Dit script roept alleen de andere scripts aan, in de goede volgorde.
# Elke stap is ook los te draaien; zie de uitleg in elk script.
./create-vms.sh                   # 3 VM's met vaste IP's (libvirt + cloud-init)
./prep-nodes.sh                   # swap, modules, containerd, kubeadm op elke node
./snapshot.sh save prepped        # terugvalpunt: nodes klaar, nog geen cluster (oefen kubeadm init zelf)
./cp-init.sh                      # kubeadm init op cp1 (zonder CNI) + etcdctl
./worker-join.sh                  # w1 en w2 joinen
./snapshot.sh save no-cni         # startpunt voor de CNI-rondes
log "Klaar. Log in met: ssh ${VM_USER}@$(node_ip "$CP_NODE")  — en ga verder met INIT stap 4."
