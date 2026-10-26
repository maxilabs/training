#!/usr/bin/env bash
# Draait OP een node (via prep-nodes.sh). Bereidt de node voor op kubeadm.
# Uitleg (wat en waarom): SCRIPTS.md
# Vereist env: K8S_MINOR (bv. v1.35), HOSTS_LINES (regels voor /etc/hosts)
# Bronnen: kubernetes.io container-runtimes + install-kubeadm; flannel README (br_netfilter)
set -euo pipefail
# Stop met een duidelijke fout als K8S_MINOR niet is meegegeven.
: "${K8S_MINOR:?K8S_MINOR ontbreekt}"
# apt mag geen vragen stellen (er kijkt niemand mee).
export DEBIAN_FRONTEND=noninteractive

# ── 1. Swap uit ───────────────────────────────────────────────────────────────
# De kubelet weigert standaard te starten als er swap aan staat: Kubernetes rekent
# met echt geheugen voor requests/limits en scheduling.
echo "== swap uit (kubelet start standaard niet met swap)"
swapoff -a                                   # nu uit
sed -ri '/\sswap\s/ s/^#?/#/' /etc/fstab     # en na een reboot ook (regel uitgecommentarieerd)

# ── 2. Kernel-modules en sysctl ───────────────────────────────────────────────
# overlay:      bestandssysteem waarmee containerd image-lagen op elkaar stapelt.
# br_netfilter: laat verkeer over een Linux-bridge door iptables gaan. Zonder dit
#               ziet kube-proxy Pod-naar-Service-verkeer niet (Flannel heeft het nodig).
# modules-load.d = ook na een reboot laden; modprobe = nu meteen laden.
echo "== kernel-modules + sysctl"
printf 'overlay\nbr_netfilter\n' >/etc/modules-load.d/k8s.conf   # br_netfilter: nodig voor Flannel
modprobe overlay; modprobe br_netfilter
# ip_forward: de node mag pakketten doorsturen (tussen Pods en naar buiten).
# bridge-nf-call-*: bridged verkeer (IPv4/IPv6) gaat door iptables (zie br_netfilter).
# 'sysctl --system' laadt alle bestanden in /etc/sysctl.d opnieuw in.
cat >/etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system >/dev/null

# ── 3. /etc/hosts ─────────────────────────────────────────────────────────────
# Nodes vinden elkaar op naam (cp1, w1, w2) zonder DNS-server.
# Eerst oude lab-regels weg (herkenbaar aan '# kubeadm-lab'), dan de nieuwe erbij.
# Zo kun je dit script vaker draaien zonder dubbele regels.
echo "== /etc/hosts"
sed -i '/# kubeadm-lab$/d' /etc/hosts
printf '%s\n' "$HOSTS_LINES" >>/etc/hosts

# ── 4. Container runtime: containerd ──────────────────────────────────────────
# De kubelet start zelf geen containers; dat doet de runtime (hier containerd), via CRI.
echo "== containerd (systemd cgroup driver)"
apt-get update -qq
apt-get install -y -qq containerd apt-transport-https ca-certificates curl gpg >/dev/null
mkdir -p /etc/containerd
# Volledige standaardconfig wegschrijven, zodat we één instelling kunnen aanpassen.
containerd config default >/etc/containerd/config.toml
# cgroups begrenzen CPU/RAM per container. Ubuntu beheert cgroups met systemd.
# kubelet (zie kubeadm-config: cgroupDriver: systemd) en containerd moeten DEZELFDE
# driver gebruiken, anders krijg je instabiele nodes en herstartende Pods.
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Controle: als de sed niets vond (andere containerd-versie), dan nu stoppen.
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || { echo "SystemdCgroup niet gezet"; exit 1; }
systemctl restart containerd; systemctl enable containerd >/dev/null

# ── 5. kubelet, kubeadm en kubectl uit de officiële repo ──────────────────────
# kubelet = agent op elke node | kubeadm = cluster opzetten/joinen/upgraden | kubectl = CLI
# pkgs.k8s.io heeft één repo per minor-versie; de oude apt.kubernetes.io bestaat niet meer.
echo "== kubelet/kubeadm/kubectl ${K8S_MINOR} via pkgs.k8s.io"
# De GPG-sleutel van de repo, zodat apt de pakketten kan controleren (signed-by).
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl >/dev/null
# 'hold': een gewone 'apt upgrade' mag deze pakketten NIET ophogen. Een clusterupgrade
# doe je bewust, in de goede volgorde, met kubeadm upgrade (zie STUDIEPLAN, upgrade-lab).
apt-mark hold kubelet kubeadm kubectl >/dev/null
# kubelet aanzetten. Hij herstart nu elke paar seconden omdat zijn config ontbreekt;
# die schrijft kubeadm init/join pas. Dat is normaal.
systemctl enable --now kubelet >/dev/null 2>&1 || true   # crasht tot kubeadm init/join: normaal

# ── 6. crictl en de examen-omgeving ───────────────────────────────────────────
# crictl praat direct met containerd. Je debug-tool als de API-server plat ligt
# (bijv. 'sudo crictl ps -a'). Dit bestand vertelt crictl waar de containerd-socket is.
echo "== crictl + examen-omgeving (alias k, completion)"
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\n' >/etc/crictl.yaml
# /etc/profile.d wordt bij elke login ingelezen. Dit is wat je op het examen ook instelt:
#   alias k + completion   -> sneller typen, Tab werkt ook voor 'k'
#   $do  -> 'k run x --image=nginx $do' toont YAML zonder iets aan te maken
#   $now -> 'k delete pod x $now' verwijdert direct, zonder 30 s wachten
cat >/etc/profile.d/k8s-exam.sh <<'EOF'
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
EOF

# Samenvatting; prep-nodes.sh toont deze laatste regel per node.
echo "== klaar: $(hostname) | $(kubeadm version -o short) | containerd $(containerd --version | awk '{print $3}')"
