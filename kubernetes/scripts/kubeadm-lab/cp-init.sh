#!/usr/bin/env bash
# kubeadm init op de control plane, ZONDER CNI (die installeer je zelf, zie INIT.md).
# Uitleg (wat en waarom): SCRIPTS.md
# Installeert ook etcdctl/etcdutl in dezelfde versie als de etcd van het cluster.
# Gebruik: ./cp-init.sh
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# ── 1. Config klaarzetten ─────────────────────────────────────────────────────
# De exacte versie (bijv. v1.35.9) halen we van de geïnstalleerde kubeadm op cp1,
# zodat de control-plane-images precies bij de pakketten passen.
CP_IP="$(node_ip "$CP_NODE")"
K8S_VERSION="$(vm_ssh "$CP_NODE" 'kubeadm version -o short')"
log "kubeadm init op $CP_NODE ($CP_IP), versie $K8S_VERSION"

# sed vervangt de __PLACEHOLDERS__ in het sjabloon door echte waarden uit lab.env.
# Het resultaat gaat via SSH (stdin) naar cp1 als ~/kubeadm-config.yaml.
sed -e "s|__CP_IP__|$CP_IP|g" -e "s|__CP_NAME__|$CP_NODE|g" -e "s|__K8S_VERSION__|$K8S_VERSION|g" \
    -e "s|__POD_CIDR__|$POD_CIDR|g" -e "s|__SERVICE_CIDR__|$SERVICE_CIDR|g" \
    kubeadm-config.yaml.tpl | vm_ssh "$CP_NODE" 'cat > ~/kubeadm-config.yaml'

# ── 2. kubeadm init ───────────────────────────────────────────────────────────
# kubeadm doet op cp1:
#   - controles (preflight): swap uit, poorten vrij, runtime bereikbaar
#   - certificaten maken in /etc/kubernetes/pki/ (CA, API-server, etcd, ...)
#   - kubeconfigs schrijven (admin.conf, kubelet.conf, ...) in /etc/kubernetes/
#   - static Pod-manifests in /etc/kubernetes/manifests/ voor etcd, kube-apiserver,
#     controller-manager en scheduler; de kubelet start die zelf, zonder API-server
#   - de add-ons CoreDNS en kube-proxy installeren
# 'tee' toont de output én bewaart hem in cp-init.log.
vm_ssh "$CP_NODE" 'sudo kubeadm init --config ~/kubeadm-config.yaml' | tee cp-init.log
# admin.conf is de kubeconfig met clusteradmin-rechten. Een kopie in ~/.kube/config
# zorgt dat 'kubectl' werkt als gebruiker ubuntu (zonder sudo).
vm_ssh "$CP_NODE" 'mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config'

# ── 3. etcdctl en etcdutl ─────────────────────────────────────────────────────
# Nodig voor de etcd-backup/restore (L-08). Ze moeten dezelfde versie hebben als de
# etcd die in het cluster draait; die versie lezen we uit het etcd-manifest.
# Het blok tussen <<'EOF' en EOF draait als script op cp1.
log "etcdctl/etcdutl installeren (zelfde versie als etcd-image)"
vm_ssh "$CP_NODE" 'bash -s' <<'EOF'
set -euo pipefail
# Uit 'image: registry.k8s.io/etcd:3.6.x-0' alleen het versienummer pakken.
V="$(sudo grep -oP 'image: .*etcd:\K[0-9.]+' /etc/kubernetes/manifests/etcd.yaml | head -1)"
[ -n "$V" ] || { echo "etcd-versie niet gevonden"; exit 1; }
# Officiële release van GitHub downloaden en alleen de twee tools installeren.
T="$(mktemp -d)"
curl -fsSL -o "$T/etcd.tgz" "https://github.com/etcd-io/etcd/releases/download/v${V}/etcd-v${V}-linux-amd64.tar.gz"
tar -xzf "$T/etcd.tgz" -C "$T" --strip-components=1
sudo install -m 0755 "$T/etcdctl" "$T/etcdutl" /usr/local/bin/
rm -rf "$T"
echo "etcdctl $(etcdctl version | head -1 | awk '{print $3}')"
EOF

# ── 4. Status ─────────────────────────────────────────────────────────────────
# NotReady en CoreDNS 'Pending' horen zo: zonder CNI is er geen Pod-netwerk.
log "Status (nodes horen NotReady te zijn: er is nog geen CNI)"
vm_ssh "$CP_NODE" 'kubectl get nodes -o wide; kubectl -n kube-system get pods'
