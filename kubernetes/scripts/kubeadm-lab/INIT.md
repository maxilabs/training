# INIT — de lab-omgeving opzetten (CKA-oefencluster op aristotle)

3 VM's (cp1, w1, w2) op libvirt/KVM, Ubuntu 24.04, kubeadm **v1.35** (examenversie CKA).
Pod-CIDR `172.30.0.0/16`, Service-CIDR `172.31.0.0/16`. Alle instellingen staan in `lab.env`.

Dit document gaat over **het opzetten en resetten van de omgeving**. Wat je leert en in welke volgorde: [STUDIEPLAN](STUDIEPLAN.md).
Wat een begrip betekent: [CONCEPTS](CONCEPTS.md) (elke stap hieronder linkt ernaar). Wat de scripts doen: [SCRIPTS](SCRIPTS.md).

| Node | IP | vCPU / RAM |
|---|---|---|
| cp1 | 192.168.122.11 | 2 / 4 GiB |
| w1  | 192.168.122.12 | 2 / 4 GiB |
| w2  | 192.168.122.13 | 2 / 4 GiB |

> Gebruik `kubectl` **op cp1** (`ssh ubuntu@192.168.122.11`), niet op aristotle: daar staat kubectl 1.37,
> en kubectl mag maar 1 minor versie van de cluster afwijken. Op cp1 heb je ook `k`, completion,
> `$do` (`--dry-run=client -o yaml`) en `$now` (`--force --grace-period=0`), net als op het examen.

---

## Stappenplan

### Stap 0 — eenmalig (al gedaan)
libvirt + qemu-base + dnsmasq geïnstalleerd, gebruiker in groep `libvirt`, netwerk `default` actief.
Controle: `virsh -c qemu:///system net-list --all` → `default active`.

### Stap 1 — bestanden neerzetten
```bash
mkdir -p ~/kubernetes/kubeadm-lab && cd ~/kubernetes/kubeadm-lab   # bestanden hierin plaatsen
chmod +x *.sh
```

### Stap 2 — cluster bouwen (± 10 min)
```bash
./bootstrap.sh
```
Dit doet: VM's maken → node-prep op alle nodes → snapshot `prepped` → `kubeadm init` (config-bestand)
→ workers joinen → snapshot `no-cni`. Per script uitgelegd in [SCRIPTS](SCRIPTS.md).

🔗 **Begrippen:** [kubeadm init](CONCEPTS.md#kubeadm-init) · [kubeadm join: hoe een node toetreedt](CONCEPTS.md#kubeadm-join) · [Container runtime en CRI](CONCEPTS.md#container-runtime) · [Static Pods](CONCEPTS.md#static-pods)

### Stap 3 — eerste troubleshooting-oefening (geen script!)
```bash
ssh ubuntu@192.168.122.11
k get nodes                      # alle 3 NotReady
k -n kube-system get pods        # coredns Pending
k describe node cp1 | grep -i -A3 'Ready'   # "network plugin not ready / cni config uninitialized"
```
**Waarom?** Er is nog geen CNI. Dit is het klassieke examenscenario.

🔗 **Begrippen:** [CNI: het Pod-netwerk](CONCEPTS.md#cni) · [Control plane vs worker (vroeger 'master')](CONCEPTS.md#control-plane) · [kubelet](CONCEPTS.md#kubelet) · [Troubleshooting-aanpak](CONCEPTS.md#troubleshooting-methode)

### Stap 4 — de drie CNI-rondes
Begin elke ronde vanaf een schone basis: `./snapshot.sh revert no-cni` (op aristotle).

🔗 **Begrippen:** [CNI: het Pod-netwerk](CONCEPTS.md#cni) · [NetworkPolicy](CONCEPTS.md#networkpolicy) · [Operator](CONCEPTS.md#operator) (Calico) · [CRD en CR (Custom Resource)](CONCEPTS.md#crd-cr) · [DaemonSet](CONCEPTS.md#daemonset)

**Ronde A — Flannel** (simpel, géén NetworkPolicy)
```bash
ssh ubuntu@192.168.122.11
curl -fsSLO https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sed -i 's#10.244.0.0/16#172.30.0.0/16#' kube-flannel.yml      # pod-CIDR moet overeenkomen met kubeadm!
grep -n '172.30.0.0/16' kube-flannel.yml && k apply -f kube-flannel.yml
k get nodes -w                   # wordt Ready
```
Stop de watch met Ctrl+C en controleer of alles op zijn plek staat. Dit draai je op cp1:
```bash
sudo ls /etc/cni/net.d/; k -n kube-flannel get pods -o wide; k -n kube-system get pods -l k8s-app=kube-dns -o wide; k describe node cp1 | grep Taints
```
Wat je zou moeten zien:

- **`/etc/cni/net.d/`:** `10-flannel.conflist`, de configuratie waar containerd op wachtte.
- **Flannel-Pods:** drie, één per node, want het is een DaemonSet.
- **CoreDNS:** `Running`, met Pod-IP’s uit `172.30.x.x`. Je Pod-CIDR is dus goed doorgekomen.
- **Taints op cp1:** alleen nog `node-role.kubernetes.io/control-plane:NoSchedule`. De `not-ready`-taint is vanzelf verdwenen.

Daarna doe je de **NetworkPolicy-test** uit INIT 
```bash
k create ns np && k -n np run web --image=nginx --expose --port 80
k -n np run client --image=busybox:1.36 --restart=Never -- sleep 3600
k -n np wait --for=condition=Ready pod/client pod/web --timeout=60s && k -n np exec client -- wget -qO- -T 3 web | head -4
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: np}
spec: {podSelector: {}, policyTypes: [Ingress]}
EOF
k -n np exec client -- wget -qO- -T 3 web | head -4
```

**Verwacht:** de policy wordt geaccepteerd (`created`), maar de laatste `wget` werkt nog. Flannel dwingt geen NetworkPolicies af.

```bash
# elke node krijgt een eigen /24 uit de Pod-CIDR
k get nodes -o custom-columns=NODE:.metadata.name,PODCIDR:.spec.podCIDR
# CoreDNS opnieuw plannen, zodat de replica's over de nodes verdeeld raken
k -n kube-system rollout restart deployment coredns
```

**Ronde B — Calico** (het examenscenario: "CNI die NetworkPolicy afdwingt, via manifests, geen Helm")
```bash
./snapshot.sh revert no-cni      # op aristotle
# op cp1:
V=v3.33.0
k create -f https://raw.githubusercontent.com/projectcalico/calico/$V/manifests/v3_projectcalico_org-v1beta1.yaml  # CRD's voor k8s 1.34/1.35
k create -f https://raw.githubusercontent.com/projectcalico/calico/$V/manifests/tigera-operator.yaml
curl -fsSLO https://raw.githubusercontent.com/projectcalico/calico/$V/manifests/custom-resources.yaml
grep -n cidr custom-resources.yaml                      # standaard 192.168.0.0/16 -> botst met je LAN!
sed -i 's#192.168.0.0/16#172.30.0.0/16#' custom-resources.yaml
k create -f custom-resources.yaml
watch kubectl get tigerastatus   # tot alles AVAILABLE=True
```
NetworkPolicy-test → nu **wordt verkeer wel geblokkeerd**. Daarna: `./snapshot.sh save calico-ready`.

**Ronde C — Cilium** (breder dan het examen, eBPF)
```bash
./snapshot.sh revert no-cni      # op aristotle
# op cp1: cilium CLI installeren (officiële stappen)
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum && sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
cilium install --help | grep -E -- '--version|--set'     # check de flagnamen van jouw CLI-versie
cilium install --version 1.20.2 --set ipam.operator.clusterPoolIPv4PodCIDRList=172.30.0.0/16
cilium status --wait && cilium connectivity test
```

### Stap 5 — examenoefeningen (vanaf snapshot `calico-ready`)

🔗 **Begrippen:** [etcd backup en restore](CONCEPTS.md#etcd-backup) · [etcd](CONCEPTS.md#etcd) · [Cluster upgraden](CONCEPTS.md#cluster-upgrade) · [Drain, cordon en uncordon](CONCEPTS.md#drain-cordon)

**etcd backup & restore** (cert-paden staan in `/etc/kubernetes/manifests/etcd.yaml`)
```bash
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key snapshot save /tmp/etcd.db
k create ns na-backup            # wijziging NA de backup
sudo etcdutl --data-dir /var/lib/etcd-restore snapshot restore /tmp/etcd.db   # etcdctl restore is deprecated
sudo sed -i 's#path: /var/lib/etcd$#path: /var/lib/etcd-restore#' /etc/kubernetes/manifests/etcd.yaml
# wacht tot etcd + apiserver herstarten, dan: k get ns  -> 'na-backup' is weg
```

**Cluster-upgrade v1.35 → v1.36** (officiële volgorde; minor versies overslaan mag niet)
1. Op elke node de repo omzetten: in `/etc/apt/sources.list.d/kubernetes.list` `v1.35` → `v1.36`, `apt-get update`.
2. cp1: `apt-mark unhold kubeadm && apt-get install -y kubeadm='1.36.x-*' && apt-mark hold kubeadm`
   → `sudo kubeadm upgrade plan` → `sudo kubeadm upgrade apply v1.36.x`
3. cp1: `k drain cp1 --ignore-daemonsets` → kubelet + kubectl upgraden → `systemctl daemon-reload && systemctl restart kubelet` → `k uncordon cp1`
4. Per worker: kubeadm upgraden → `sudo kubeadm upgrade node` → drain (vanaf cp1) → kubelet/kubectl → restart → uncordon.

Tip: `./snapshot.sh save pre-upgrade` vooraf, zodat je de upgrade vaker kunt oefenen.

**Overige (INIT-oefeningen, zelf typen)**: RBAC (`k create role/rolebinding`, `k auth can-i --as`),
node-onderhoud (`cordon/drain/uncordon`), taints/tolerations, static Pods (`/etc/kubernetes/manifests`),
kapotte kubelet (`sudo systemctl stop kubelet` op w1 → diagnose vanaf cp1 → `journalctl -u kubelet`).

### Stap 6 — add-ons en troubleshooting (vanaf `calico-ready`)
```bash
./addons.sh all              # of per stuk: helm metrics-server local-path metallb gateway-crds traefik
./addons.sh status
./snapshot.sh save addons    # basis voor L-10, L-16, L-18, L-23 en blok 7
./break.sh random            # troubleshooting-oefening; ./break.sh check <nr> als je denkt dat het werkt
```
Volg verder het [STUDIEPLAN](STUDIEPLAN.md).

🔗 **Begrippen:** [Helm](CONCEPTS.md#helm) · [metrics-server](CONCEPTS.md#metrics-server) · [StorageClass en dynamische provisioning](CONCEPTS.md#storageclass) · [Service type LoadBalancer en MetalLB](CONCEPTS.md#loadbalancer) · [Gateway API](CONCEPTS.md#gateway-api) · [Ingress en ingress-controller](CONCEPTS.md#ingress) · [Troubleshooting-aanpak](CONCEPTS.md#troubleshooting-methode)

### NetworkPolicy-test (voor ronde A en B)

🔗 **Begrippen:** [NetworkPolicy](CONCEPTS.md#networkpolicy) · [CNI: het Pod-netwerk](CONCEPTS.md#cni) · [Service](CONCEPTS.md#service)
```bash
k create ns np && k -n np run web --image=nginx --expose --port 80
k -n np run client --image=busybox:1.36 --restart=Never -- sleep 3600
k -n np exec client -- wget -qO- -T 3 web          # werkt
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: np}
spec: {podSelector: {}, policyTypes: [Ingress]}
EOF
k -n np exec client -- wget -qO- -T 3 web          # Flannel: werkt nog | Calico: timeout
```

### Stap 8 — IaC en CI/CD voorbereiden (hoort bij blok 8)

Eenmalig, voor de labs L-28 t/m L-32. Uitleg per onderdeel in [CONCEPTS](CONCEPTS.md#blok-8).

🔗 **Begrippen:** [Het lagenmodel](CONCEPTS.md#iac-lagen) · [Self-hosted runner](CONCEPTS.md#self-hosted-runner) · [OIDC-federatie](CONCEPTS.md#oidc-federatie) · [Terraform-state](CONCEPTS.md#terraform-state)

**8a. Deze map als privé GitHub-repo** (op aristotle, met de GitHub CLI; `yay -S github-cli` als je hem nog niet hebt)
```bash
cd ~/kubernetes/kubeadm-lab && git init -b main && git add . && git commit -m "kubeadm-lab" && gh repo create kubeadm-lab --private --source=. --push
```
**Privé** is belangrijk: met een self-hosted runner kan bij een publieke repo iedereen via een pull request code op aristotle laten draaien.

**8b. Self-hosted runner op aristotle** (voor scenario A)
1. Voorwaarden: de gebruiker van de runner zit in de groep `libvirt` (`id -nG`) en heeft een SSH-key (`~/.ssh/id_ed25519.pub`).
   Andere key? Zet in GitHub de repository-variabele `SSH_PUBKEY_FILE` op het pad.
2. GitHub → repo → **Settings → Actions → Runners → New self-hosted runner** → Linux x64. Volg de getoonde commando's
   (download en `config.sh` met een eenmalig token). Geef bij `config.sh` het label mee: `--labels aristotle`.
3. Als service laten draaien, zodat hij na een reboot weer start:
   ```bash
   sudo ./svc.sh install "$USER" && sudo ./svc.sh start && systemctl list-units 'actions.runner.*' --no-pager
   ```
4. Controle in GitHub: de runner staat op **Idle**, met de labels `self-hosted`, `Linux`, `X64`, `aristotle`.

**8c. Azure voorbereiden** (voor scenario B; eigen subscriptie)
```bash
az login && GH_REPO=<account>/kubeadm-lab ./iac/aks-azure/bootstrap.sh
```
Het script maakt de state-opslag, de resource group, de app-registratie met twee federated credentials en de rollen,
en print aan het eind een `gh variable set`-oneliner voor de repository-variabelen. Daarna nog:
- **Settings → Environments → New environment `azure`**: zet bij *Deployment branches* alleen `main`, en eventueel
  jezelf als *Required reviewer* (dan wacht elke apply op jouw klik).
- Repository-variabele `GITOPS_REPO_URL` = je **publieke** gitops-repo (bijv. `k8s-lab-gitops` uit L-25).
- Kosten in de gaten houden: stel in de Azure-portal een budget met e-mailwaarschuwing in op je subscriptie,
  en ruim na elke sessie op met de `destroy`-run (L-31).

**8d. Controle**
```bash
gh variable list && gh api repos/{owner}/{repo}/environments --jq '.environments[].name'
```

---

## Snapshots

| Snapshot | Moment | Gebruik |
|---|---|---|
| `prepped` | nodes voorbereid, geen cluster | `kubeadm init/join` zelf met de hand oefenen |
| `no-cni` | cluster up, geen CNI | startpunt CNI-rondes |
| `calico-ready` | cluster + Calico | basis voor etcd, upgrade, RBAC, break.sh |
| `addons` | + add-ons (addons.sh all) | HPA, Ingress/Gateway, storage, monitoring |
| `platform` | + Argo CD / monitoring | blok 7 |

`./snapshot.sh list | save <naam> | revert <naam> | delete <naam>` — alles weg: `./destroy-vms.sh`.

## Bestanden

| Bestand | Draait op | Doel |
|---|---|---|
| `lab.env` | — | alle instellingen |
| `bootstrap.sh` | aristotle | fase 1 in één keer |
| `create-vms.sh` | aristotle | image + 3 VM's (cloud-init, vaste IP's) |
| `prep-nodes.sh` → `node-prep.sh` | aristotle → nodes | swap, modules, sysctl, containerd, kubeadm v1.35, crictl, alias |
| `kubeadm-config.yaml.tpl` | — | multi-document kubeadm-config (v1beta4) |
| `cp-init.sh` | aristotle → cp1 | `kubeadm init --config`, kubeconfig, etcdctl/etcdutl |
| `worker-join.sh` | aristotle | join met vers token |
| `snapshot.sh` / `destroy-vms.sh` | aristotle | snapshots / opruimen |
| `addons.sh` | aristotle → cp1 | Helm, metrics-server, local-path, MetalLB, Gateway API CRD's, Traefik |
| `break.sh` | aristotle → nodes | 10 troubleshooting-scenario's (random, check, hint, restore) |
| `README.md` | — | index van de map en uitleg van de studiemethode |
| `CONCEPTS.md` | — | alle begrippen als losse objecten (kern van de methode) |
| `STUDIEPLAN.md` | — | leidend leerplan: volgorde, blokken, labs L-01–L-27, Kubestronaut-traject |
| `INIT.md` | — | dit document: de omgeving opzetten en resetten |
| `SCRIPTS.md` | — | uitleg per script: wat, waarom, handmatig equivalent, controleren |
| [`iac/lab-libvirt/`](iac/lab-libvirt/README.md) | aristotle (runner) | scenario A: VM's van een tweede cluster met Terraform (libvirt-provider 0.9) + `wait-nodes.sh` |
| [`iac/aks-azure/`](iac/aks-azure/README.md) | GitHub-runner | scenario B: AKS met Flux-extensie; `bootstrap.sh` voor de eenmalige Azure-voorbereiding |
| [`iac/aks-azurelocal/`](iac/aks-azurelocal/README.md) | — | scenario C: AKS op Azure Local via de AVM-module (lezen en valideren) |
| `.github/workflows/` | GitHub | `terraform-checks.yml`, `lab-libvirt.yml`, `aks-azure.yml` |
| `.gitignore` | — | houdt state, tfvars, plannen en lab-logs uit git |

## Bronnen (geverifieerd 15-10-2026)
- Container runtimes (ip_forward, SystemdCgroup, containerd-socket): https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- kubeadm installeren (pkgs.k8s.io, swap): https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- pkgs.k8s.io per minor versie: https://kubernetes.io/blog/2023/08/15/pkgs-k8s-io-introduction/
- kubeadm extraArgs (v1beta4, name/value): https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags/
- kubeadm upgrade: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
- etcd backup/restore (etcdutl): https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
- MutatingAdmissionPolicy (beta in 1.34, standaard uit): https://v1-34.docs.kubernetes.io/docs/reference/access-authn-authz/mutating-admission-policy/
- Calico 3.33 install + requirements (getest op k8s 1.35–1.37): https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises
- Flannel (release-manifest, br_netfilter): https://github.com/flannel-io/flannel
- Cilium 1.20 install: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
- virt-install `--cloud-init`: https://github.com/virt-manager/virt-manager/blob/main/man/virt-install.rst
- Ubuntu 24.04 cloud image: https://cloud-images.ubuntu.com/noble/current/
- metrics-server (install, --kubelet-insecure-tls): https://github.com/kubernetes-sigs/metrics-server
- local-path-provisioner v0.0.36: https://github.com/rancher/local-path-provisioner
- MetalLB v0.16.1 (installatie, L2-config): https://metallb.io/installation/ · https://metallb.io/configuration/
- Gateway API v1.6.1 (standard channel): https://gateway-api.sigs.k8s.io/guides/getting-started/
- Helm 4 installer: https://helm.sh/docs/intro/install/
- Traefik Helm-chart (Ingress + Gateway provider): https://github.com/traefik/traefik-helm-chart
- Ingress-NGINX retirement: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/

Extra gecontroleerd: `custom-resources.yaml` bestaat in Calico v3.33.0 (`cidr: 192.168.0.0/16`, VXLANCrossSubnet);
het Flannel-releasemanifest gebruikt `"Network": "10.244.0.0/16"` (dus de `sed` klopt).
**Niet 100% geverifieerd**: de flagnamen van de cilium CLI — check met `cilium install --help`.

Bronnen blok 8 (geverifieerd 15-10-2026):
- libvirt-provider 0.9 (herschrijving, nieuw schema): https://github.com/dmacvicar/terraform-provider-libvirt (schema uitgelezen uit v0.9.9; `iac/lab-libvirt` gevalideerd)
- azurerm 5.10 (`kubernetes_cluster`, `kubernetes_cluster_extension`, `kubernetes_flux_configuration`): docs in de provider-repo, tag v5.10.0
- Backend azurerm met OIDC: https://developer.hashicorp.com/terraform/language/backend/azurerm
- GitHub OIDC en subject-claims: https://docs.github.com/en/actions/reference/security/oidc
- Federated credentials in Entra: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust
- Self-hosted runners (netwerk, updates, publieke repo's): https://docs.github.com/en/actions/reference/runners/self-hosted-runners · https://docs.github.com/en/actions/reference/security/secure-use
- AKS system node pools (min. 4 vCPU/4 GB, geen B-series): https://learn.microsoft.com/en-us/azure/aks/use-system-pools
- AKS Arc met Terraform (preview) + AVM-module v2.0.4: https://learn.microsoft.com/en-us/azure/aks/aksarc/create-clusters-terraform

**Niet uitgevoerd hier:** scenario B en C zijn niet tegen echte providers gevalideerd (de azurerm-provider en de
Terraform-registry zijn vanuit mijn werkomgeving niet bereikbaar). De argumenten zijn gecontroleerd tegen de
provider-documentatie van v5.10.0 en de AVM-modulecode; `terraform-checks.yml` valideert ze bij je eerste PR echt.
