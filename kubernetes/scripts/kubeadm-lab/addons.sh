#!/usr/bin/env bash
# Fase 2: add-ons voor de labs. Draait vanaf aristotle, voert alles uit op cp1.
# Uitleg (wat en waarom): SCRIPTS.md
# Vereist: een werkend cluster MET CNI (bijv. snapshot 'calico-ready').
#
# Gebruik: ./addons.sh <add-on>...   of   ./addons.sh all   of   ./addons.sh status
#   helm            Helm 4 op cp1                         (L-05, L-26)
#   metrics-server  kubectl top + HPA                     (L-10, L-23)
#   local-path      dynamische StorageClass 'local-path'  (L-18)
#   metallb         Service type=LoadBalancer krijgt IP   (L-16)
#   gateway-crds    Gateway API CRD's (standard channel)  (L-16)
#   traefik         Ingress- én Gateway API-controller    (L-16)  [vereist: helm, metallb, gateway-crds]
#
# Tip: oefen eerst zelf met de hand (zie STUDIEPLAN.md); gebruik dit script als je de add-on alleen nodig hebt.
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# on_cp: voert een commando (of een heel blok tussen "...") uit op cp1, waar kubectl werkt.
# Let op: binnen "..." vult aristotle $VARIABELEN in VOORDAT het naar cp1 gaat;
# daarom zie je soms \" of \$ als iets pas op cp1 moet worden uitgewerkt.
on_cp() { vm_ssh "$CP_NODE" "$@"; }

# ── Helm ──────────────────────────────────────────────────────────────────────
# Helm = package manager voor Kubernetes. Een 'chart' is een pakket YAML-sjablonen
# met instelbare waarden. We gebruiken het officiële installatiescript van Helm 4.
# Staat helm er al, dan alleen de versie tonen en klaar.
add_helm() {
  log "Helm 4 installeren op $CP_NODE"
  on_cp "command -v helm >/dev/null && helm version --short && exit 0
         curl -fsSL -o /tmp/get_helm.sh '$HELM_INSTALLER' && chmod 700 /tmp/get_helm.sh && /tmp/get_helm.sh && helm version --short"
}

# ── metrics-server ────────────────────────────────────────────────────────────
# Haalt elke paar seconden CPU/RAM-gebruik op bij elke kubelet en biedt dat aan via
# de Metrics API. Nodig voor 'kubectl top' en de HorizontalPodAutoscaler (HPA).
# Bewaart geen geschiedenis (daarvoor is Prometheus, blok 7).
# Stappen: officieel manifest toepassen -> in het lab de TLS-controle van de kubelets
# uitzetten (kubeadm-kubelets hebben zelfondertekende certs) -> wachten tot hij draait.
# De 'grep -q ... ||' zorgt dat de patch maar één keer gebeurt.
add_metrics_server() {
  log "metrics-server installeren"
  on_cp "kubectl apply --filename='$METRICS_SERVER_URL'
         # kubeadm-kubelets hebben self-signed serving-certificaten -> alleen in een lab: CA-controle uit
         kubectl --namespace=kube-system get deployment metrics-server --output=jsonpath='{.spec.template.spec.containers[0].args}' | grep -q kubelet-insecure-tls ||
         kubectl --namespace=kube-system patch deployment metrics-server --type=json \
           --patch='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'
         kubectl --namespace=kube-system rollout status deployment/metrics-server --timeout=180s"
  log "Test (kan een minuut duren voor er data is): kubectl top nodes"
}

# ── local-path-provisioner ────────────────────────────────────────────────────
# Een StorageClass met 'dynamische provisioning': maak je een PVC, dan maakt deze
# provisioner automatisch een PV (een map op de node). We maken hem de standaard-
# StorageClass, zodat een PVC zonder storageClassName hem ook gebruikt.
add_local_path() {
  log "local-path-provisioner $LOCAL_PATH_VERSION installeren"
  on_cp "kubectl apply --filename=https://raw.githubusercontent.com/rancher/local-path-provisioner/$LOCAL_PATH_VERSION/deploy/local-path-storage.yaml
         kubectl --namespace=local-path-storage rollout status deployment/local-path-provisioner --timeout=180s
         kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --overwrite
         kubectl get storageclass"
}

# ── MetalLB ───────────────────────────────────────────────────────────────────
# In de cloud geeft de provider een Service van type LoadBalancer een extern IP.
# Op je eigen VM's doet niemand dat (EXTERNAL-IP blijft <pending>); MetalLB wel.
#   IPAddressPool  -> uit welke range MetalLB IP's uitdeelt (METALLB_RANGE in lab.env)
#   L2Advertisement -> een node beantwoordt ARP-vragen voor dat IP, zodat het op het
#                      libvirt-netwerk bereikbaar is (geen router/BGP nodig)
# Eerst wachten tot de controller en de speakers draaien, anders weigert de API de pool.
add_metallb() {
  log "MetalLB $METALLB_VERSION (native, L2) installeren, pool $METALLB_RANGE"
  on_cp "kubectl apply --filename=https://raw.githubusercontent.com/metallb/metallb/$METALLB_VERSION/config/manifests/metallb-native.yaml
         kubectl --namespace=metallb-system rollout status deployment/controller --timeout=180s
         kubectl --namespace=metallb-system rollout status daemonset/speaker --timeout=180s
         cat <<EOF | kubectl apply --filename=-
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: lab-pool, namespace: metallb-system}
spec:
  addresses: [\"$METALLB_RANGE\"]
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: lab-l2, namespace: metallb-system}
spec:
  ipAddressPools: [lab-pool]
EOF"
}

# ── Gateway API CRD's ─────────────────────────────────────────────────────────
# Gateway API is de opvolger van Ingress (GatewayClass, Gateway, HTTPRoute, ...).
# Die types zitten niet standaard in Kubernetes: je installeert ze als CRD's.
# --server-side: de API-server doet de merge; nodig omdat deze CRD's te groot zijn
# voor de annotatie die een gewone 'kubectl apply' bijhoudt.
add_gateway_crds() {
  log "Gateway API CRD's $GATEWAY_API_VERSION (standard channel) installeren"
  on_cp "kubectl apply --server-side --filename=https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml
         kubectl get crd | grep gateway.networking.k8s.io"
}

# ── Traefik ───────────────────────────────────────────────────────────────────
# Ingress-controller: de software die Ingress- en Gateway-objecten echt uitvoert
# (zonder controller doet een Ingress niets). ingress-nginx is in maart 2026 met
# pensioen gegaan; Traefik ondersteunt zowel Ingress als Gateway API.
# Eerst controleren of helm en de Gateway-CRD's er zijn, dan via Helm installeren:
#   upgrade --install  -> installeren, of bijwerken als hij er al is
#   kubernetesGateway  -> Traefik ook als Gateway API-controller laten werken
#   --wait             -> pas klaar als alles draait
# De Service van Traefik is type LoadBalancer en krijgt zijn IP van MetalLB.
add_traefik() {
  log "Traefik installeren (Ingress + Gateway API)"
  on_cp "command -v helm >/dev/null || { echo 'Helm ontbreekt: ./addons.sh helm'; exit 1; }
         kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || { echo 'Gateway CRDs ontbreken: ./addons.sh gateway-crds'; exit 1; }
         helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
         helm repo update traefik >/dev/null
         helm upgrade --install traefik traefik/traefik --namespace=traefik --create-namespace \
           --set providers.kubernetesGateway.enabled=true --wait --timeout 5m
         kubectl get ingressclass; kubectl get gatewayclass,gateway --all-namespaces
         kubectl --namespace=traefik get service traefik   # EXTERNAL-IP komt uit de MetalLB-pool"
}

# ── status ────────────────────────────────────────────────────────────────────
# Overzicht van wat er geïnstalleerd is. Tussen '...' (enkele quotes) wordt niets
# op aristotle ingevuld; alles draait letterlijk zo op cp1.
status() {
  on_cp 'echo "== helm: $(helm version --short 2>/dev/null || echo niet geinstalleerd)"
         for ns in kube-system local-path-storage metallb-system traefik; do
           echo "== $ns"; kubectl --namespace=$ns get deployments,daemonsets 2>/dev/null | grep -Ev "coredns|kube-proxy|calico|cilium|flannel" || true
         done
         echo "== storageclass"; kubectl get storageclass 2>/dev/null
         echo "== ingressclass / gatewayclass"; kubectl get ingressclass,gatewayclass 2>/dev/null
         echo "== kubectl top nodes"; kubectl top nodes 2>/dev/null || echo "(metrics-server niet actief)"'
}

# ── Hoofdprogramma ────────────────────────────────────────────────────────────
# Geen argument? Toon de gebruiksuitleg bovenaan dit bestand.
[ $# -gt 0 ] || { sed -n '2,14p' "$0"; exit 1; }
# Zonder CNI zijn de nodes NotReady en starten add-on-Pods niet: dan meteen stoppen.
vm_ssh "$CP_NODE" 'kubectl get nodes --no-headers' | grep -q ' Ready ' || die "cluster niet Ready: eerst een CNI installeren (INIT §4)"

# Elk argument is een add-on; ze worden in de opgegeven volgorde geïnstalleerd.
for a in "$@"; do
  case "$a" in
    all)            add_helm; add_metrics_server; add_local_path; add_metallb; add_gateway_crds; add_traefik ;;
    helm)           add_helm ;;
    metrics-server) add_metrics_server ;;
    local-path)     add_local_path ;;
    metallb)        add_metallb ;;
    gateway-crds)   add_gateway_crds ;;
    traefik)        add_traefik ;;
    status)         status ;;
    *)              die "onbekende add-on: $a" ;;
  esac
done
log "Klaar. Tip: ./snapshot.sh save addons"
