# CKA-studieplan

**Leidend document** voor je studie: CKA (blok 0–6), platform-vaardigheden (blok 7) en het vervolgtraject
naar Kubestronaut (onderaan). Wat je moet leren, in welke volgorde, en waar je het oefent.
Labverwijzingen: **INIT §x** = stappen in [INIT.md](INIT.md); **L-xx** = nieuwe labs in dit bestand.
Basis: officiële CKA-curriculum (Kubernetes v1.35), opgehaald 15-10-2026.

> Commando's staan voluit (`kubectl`). Op cp1 en op het examen mag je `k` gebruiken.
> Start elk lab vanaf een snapshot (`./snapshot.sh revert calico-ready`, tenzij anders vermeld), zodat je
> labs elkaar niet beïnvloeden. Uren zijn een **eigen inschatting**, geen officieel advies.

---

## Overzicht

| Blok | Domein (gewicht) | Indicatie | Labs |
|---|---|---|---|
| 0 | Basis: kubectl-vlotheid | 4–6 u | L-01 |
| 1 | Cluster Architecture, Installation & Configuration (25%) | 12–16 u | INIT §2, §5 · L-02 t/m L-06, L-33 |
| 2 | Workloads & Scheduling (15%) | 8–10 u | L-07 t/m L-12, L-34 t/m L-36 |
| 3 | Services & Networking (20%) | 10–12 u | INIT §4 + NetworkPolicy-test · L-13 t/m L-16 |
| 4 | Storage (10%) | 4–6 u | L-17, L-18 |
| 5 | Troubleshooting (30%) | 12–16 u | INIT §3, §5 · L-19 t/m L-23, L-37 |
| 6 | Examentraining | 8–12 u | killer.sh, Killercoda, herhaling |
| 7 | Platform: GitOps + monitoring (geen CKA-stof, wel essentieel in de praktijk) | 10–14 u | L-24 t/m L-27 |
| 9 | Secret management: ESO + Azure Key Vault (geen CKA-stof, wel dagelijkse praktijk) | 8–12 u | S-01 t/m S-20 |
| 8 | IaC en CI/CD: clusters en resources uitrollen (lab, AKS, AKS op Azure Local; geen CKA-stof) | 10–14 u | INIT §8 · L-28 t/m L-32 |

**Volgorde:** blok 0 → 1 → 2 → 3 → 4 → 5 → 6. Troubleshooting komt bewust na de andere blokken: je kunt pas
repareren wat je begrijpt. Herhaal daarna blok 5 tot het snel gaat; het is 30% van het examen.
Blok 7 kun je na blok 1 al starten (je hebt dan Helm), maar plan het naast of na de CKA, niet in plaats van.
Blok 8 bouwt op blok 1 (kubeadm) en blok 7 (GitOps); ook dit naast of na de CKA.

Labs gemarkeerd met **(add-on: …)** hebben een add-on nodig. Installeer die met `./addons.sh <naam>` (of `all`),
of oefen de installatie eerst zelf met de hand. Troubleshooting-scenario's start je met `./break.sh` (zie blok 5).

---

## Blok 0 — kubectl-vlotheid

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 0 in CONCEPTS](CONCEPTS.md#blok-0)

- Opbouw van een commando: werkwoord · resourcetype · naam · namespace · uitvoer (zie het Docker→Kubernetes-document).
- Imperatief (`kubectl create/run/expose`) vs declaratief (`kubectl apply`).
- YAML laten genereren met `--dry-run=client --output=yaml`.
- Contexts en namespaces in kubeconfig.
- `kubectl explain` en `kubectl api-resources` als ingebouwde naslag.

**L-01 — Snelheidsdrill** (herhaal tot elk commando < 30 s kost)

🔗 **Begrippen:** [kubectl, de CLI](CONCEPTS.md#kubectl) · [Imperatief vs declaratief](CONCEPTS.md#imperatief-declaratief) · [YAML genereren met dry-run](CONCEPTS.md#dry-run) · [kubeconfig en contexts](CONCEPTS.md#kubeconfig) · [Namespace](CONCEPTS.md#namespace) · [kubectl explain en api-resources](CONCEPTS.md#kubectl-explain)
```bash
kubectl config get-contexts && kubectl config set-context --current --namespace=drill
kubectl create namespace drill
kubectl run web --image=nginx:1.27 --dry-run=client --output=yaml > pod.yaml
kubectl create deployment web --image=nginx:1.27 --replicas=2 --dry-run=client --output=yaml > deploy.yaml
kubectl create service clusterip web --tcp=80:80 --dry-run=client --output=yaml > svc.yaml
kubectl create job hallo --image=busybox:1.36 --dry-run=client --output=yaml -- echo hallo > job.yaml
kubectl create cronjob tik --image=busybox:1.36 --schedule="*/5 * * * *" --dry-run=client --output=yaml -- date > cron.yaml
kubectl create configmap app --from-literal=MODE=prod --dry-run=client --output=yaml > cm.yaml
kubectl create secret generic db --from-literal=pw=geheim --dry-run=client --output=yaml > secret.yaml
kubectl explain deployment.spec.strategy --recursive
```
Docs: [kubectl Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) ·
[kubectl for Docker users](https://kubernetes.io/docs/reference/kubectl/docker-cli-to-kubectl/)

---

## Blok 1 — Cluster Architecture, Installation & Configuration (25%)

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 1 in CONCEPTS](CONCEPTS.md#blok-1)

- Control-plane-componenten: kube-apiserver, etcd, kube-scheduler, kube-controller-manager; op nodes kubelet, kube-proxy, container runtime.
- Static Pods: de control plane draait als manifests in `/etc/kubernetes/manifests`, beheerd door de kubelet.
- kubeadm: `init` (ook met configbestand), `join`, tokens, certificaten (`kubeadm certs check-expiration`).
- Cluster-lifecycle: upgrade per minor versie (repo omzetten, kubeadm → control plane → kubelets), drain/uncordon.
- etcd backup (`etcdctl snapshot save`) en restore (`etcdutl snapshot restore`).
- RBAC: Role/ClusterRole, RoleBinding/ClusterRoleBinding, ServiceAccounts, `kubectl auth can-i`.
- Extensie-interfaces: CNI (netwerk), CSI (opslag), CRI (runtime).
- Helm en Kustomize om componenten te installeren.
- CRD's en operators.
- HA control plane: concept (meerdere control planes achter een load balancer, stacked vs extern etcd).
- Gebruikers met een client-certificaat via de CSR-API; owner references, garbage collection en finalizers;
  de Cloud Controller Manager (het verschil tussen kubeadm-lab en AKS).

🔗 **Uitgewerkt in CONCEPTS:** [kubeadm join: hoe een node toetreedt](CONCEPTS.md#kubeadm-join) · [Control plane vs worker (vroeger 'master')](CONCEPTS.md#control-plane)

**Labs**
- **INIT §2** — cluster bouwen met `bootstrap.sh`.
- **L-02 — kubeadm met de hand** (vanaf snapshot `prepped`)
  ```bash
  ./snapshot.sh revert prepped                 # op aristotle
  # op cp1:
  kubeadm config print init-defaults > init.yaml   # bekijk de structuur, vergelijk met kubeadm-config.yaml.tpl
  sudo kubeadm init --pod-network-cidr=172.30.0.0/16 --service-cidr=172.31.0.0/16
  sudo kubeadm token create --print-join-command   # voer de uitvoer uit op w1 en w2
  ```
  Let op: zonder configbestand ontbreekt de feature gate die Calico 3.33 op 1.35 nodig heeft. Gebruik hier Flannel
  (INIT §4, ronde A), of voeg de gate toe — dat laatste is meteen een goede oefening.

  🔗 **Begrippen:** [kubeadm init](CONCEPTS.md#kubeadm-init) · [kubeadm join: hoe een node toetreedt](CONCEPTS.md#kubeadm-join) · [Control plane vs worker (vroeger 'master')](CONCEPTS.md#control-plane) · [CNI: het Pod-netwerk](CONCEPTS.md#cni)
- **L-03 — control plane verkennen**
  ```bash
  ls /etc/kubernetes/manifests/
  kubectl --namespace=kube-system get pods --output=wide
  sudo kubeadm certs check-expiration
  sudo crictl ps                                # dezelfde componenten, gezien vanuit containerd
  ```
  Join en rollen controleren (zie [kubeadm join: hoe een node toetreedt](CONCEPTS.md#kubeadm-join) en [Control plane vs worker (vroeger 'master')](CONCEPTS.md#control-plane)):
  ```bash
  kubectl get nodes --output=wide && kubectl get csr                     # alle nodes + CSR's 'Approved,Issued'
  kubectl describe node w1 | grep -A6 Conditions                         # zonder CNI: Ready=False, "cni plugin not initialized"
  sudo kubeadm token list                                                # tokens en hun geldigheid
  kubectl --namespace=kube-public get configmap cluster-info --output=yaml | head -20   # wat een worker bij discovery leest
  kubectl get nodes --show-labels | grep control-plane                   # het rollabel
  kubectl get node cp1 --output=jsonpath='{range .spec.taints[*]}{.key}:{.effect}{"\n"}{end}'   # ALLE taints
  # de CA-hash uit het join-commando zelf uitrekenen (commando uit de kubeadm-docs):
  openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'
  ```
  Op een worker: `systemctl is-active kubelet && sudo ls /etc/kubernetes/kubelet.conf /var/lib/kubelet/pki/`
  (de kubelet draait en heeft zijn eigen kubeconfig en certificaat).

  🔗 **Begrippen:** [Control plane vs worker (vroeger 'master')](CONCEPTS.md#control-plane) · [Static Pods](CONCEPTS.md#static-pods) · [Certificaten en PKI](CONCEPTS.md#certificaten-pki) · [crictl](CONCEPTS.md#crictl) · [kubeadm join: hoe een node toetreedt](CONCEPTS.md#kubeadm-join) · [Taints en tolerations](CONCEPTS.md#taints-tolerations)
- **INIT §5** — etcd backup/restore en de upgrade v1.35 → v1.36 (maak eerst `./snapshot.sh save pre-upgrade`).
- **L-04 — RBAC**
  ```bash
  kubectl create namespace dev
  kubectl create serviceaccount ci --namespace=dev
  kubectl create role pod-lezer --verb=get,list,watch --resource=pods --namespace=dev
  kubectl create rolebinding ci-leest --role=pod-lezer --serviceaccount=dev:ci --namespace=dev
  kubectl auth can-i list pods --namespace=dev --as=system:serviceaccount:dev:ci      # yes
  kubectl auth can-i delete pods --namespace=dev --as=system:serviceaccount:dev:ci    # no
  kubectl auth can-i list pods --namespace=default --as=system:serviceaccount:dev:ci  # no
  ```
  Uitbreiding: een ClusterRole + ClusterRoleBinding, en een gebruiker met een certificaat via een
  CertificateSigningRequest ([docs](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/)).

  🔗 **Begrippen:** [RBAC](CONCEPTS.md#rbac) · [ServiceAccount](CONCEPTS.md#serviceaccount) · [Namespace](CONCEPTS.md#namespace)
- **L-05 — Helm en Kustomize** (add-on: `helm`)
  - Helm 4 installeren volgens [helm.sh/docs](https://helm.sh/docs/intro/install/) (of `./addons.sh helm`), daarna een chart installeren,
    upgraden met een andere waarde (`--set`) en terugdraaien (`helm rollback`).
  - Kustomize: een map `base/` met deployment + service en een `overlays/prod/` die replicas en namespace aanpast;
    `kubectl apply --kustomize=overlays/prod`. Docs: [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

  🔗 **Begrippen:** [Helm](CONCEPTS.md#helm) · [Kustomize](CONCEPTS.md#kustomize)
- **L-06 — CRD en operator**
  - Schrijf een eigen CRD (bijv. `Backup`), maak er een object van, bekijk het met `kubectl explain` en `kubectl get backups`.
    Docs: [CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
  - Operator in de praktijk: je installeerde er al een (Calico tigera-operator, INIT §4B). Extra (sluit aan op je
    sollicitatievraag): CloudNativePG volgens hun quickstart, en een PostgreSQL-`Cluster` met 2 instances.

  🔗 **Begrippen:** [CRD en CR (Custom Resource)](CONCEPTS.md#crd-cr) · [Operator](CONCEPTS.md#operator)

- **L-33 — Gebruiker met een certificaat (CSR-API)**
  ```bash
  openssl genrsa -out jan.key 3072 && openssl req -new -key jan.key -out jan.csr -subj "/CN=jan/O=dev-team"
  printf 'apiVersion: certificates.k8s.io/v1\nkind: CertificateSigningRequest\nmetadata: {name: jan}\nspec:\n  request: %s\n  signerName: kubernetes.io/kube-apiserver-client\n  expirationSeconds: 86400\n  usages: [client auth]\n' "$(base64 -w0 < jan.csr)" | kubectl apply -f -
  kubectl get csr jan && kubectl certificate approve jan && kubectl get csr jan --output=jsonpath='{.status.certificate}' | base64 -d > jan.crt
  kubectl config set-credentials jan --client-key=jan.key --client-certificate=jan.crt --embed-certs
  kubectl config set-context jan --cluster=kubernetes --user=jan
  kubectl create role pod-lezer --verb=get,list --resource=pods --namespace=dev --dry-run=client --output=yaml | kubectl apply -f -
  kubectl create rolebinding jan-leest --role=pod-lezer --user=jan --namespace=dev
  kubectl --context=jan get pods --namespace=dev && kubectl --context=jan get pods --namespace=default   # mag / mag niet
  ```
  Probeer ook een RoleBinding op de **groep** `dev-team` (`--group=dev-team`) in plaats van op `jan`.

  🔗 **Begrippen:** [Gebruikers en certificaten via de CSR-API](CONCEPTS.md#csr-gebruikers) · [RBAC](CONCEPTS.md#rbac) · [kubeconfig en contexts](CONCEPTS.md#kubeconfig) · [Certificaten en PKI](CONCEPTS.md#certificaten-pki)

Docs: [kubeadm upgrade](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/) ·
[etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) ·
[RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
[Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) ·
[HA-topologie](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)

---

## Blok 2 — Workloads & Scheduling (15%)

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 2 in CONCEPTS](CONCEPTS.md#blok-2)

- Deployments: rolling update, rollback, `maxSurge`/`maxUnavailable`, revision history.
- ConfigMaps en Secrets als env-var en als volume (en het verschil bij wijzigen).
- Workload-autoscaling: HorizontalPodAutoscaler (vereist metrics-server).
- Zelfherstellende primitieven: ReplicaSet, DaemonSet, StatefulSet, Job, CronJob, probes, `restartPolicy`.
- Pod-admission en scheduling: requests/limits, ResourceQuota, LimitRange, nodeSelector, node-affinity,
  taints/tolerations, PriorityClass.
- `command`/`args` vs `ENTRYPOINT`/`CMD`.
- Init- en sidecar-containers, Pod-levenscyclus en beëindiging (`preStop`, grace period), SecurityContext,
  PodDisruptionBudget, topology spread constraints, images en `imagePullSecrets`.

**Labs**
- **L-07 — Rollouts**
  ```bash
  kubectl create deployment web --image=nginx:1.26 --replicas=4
  kubectl set image deployment/web nginx=nginx:1.27 && kubectl rollout status deployment/web
  kubectl set image deployment/web nginx=nginx:bestaat-niet     # zie hoe de rollout vastloopt
  kubectl rollout history deployment/web && kubectl rollout undo deployment/web
  ```
  Owner references: `kubectl delete deployment web --cascade=orphan` en zie dat ReplicaSet en Pods blijven staan.

  🔗 **Begrippen:** [Deployment en rolling updates](CONCEPTS.md#deployment) · [ReplicaSet](CONCEPTS.md#replicaset) · [Owner references, garbage collection en finalizers](CONCEPTS.md#owners-finalizers)
- **L-08 — ConfigMap/Secret als env én als volume:** wijzig de ConfigMap en kijk na ± 1 minuut in de container:
  het gemounte bestand verandert, de env-var niet (pas na een herstart).

  🔗 **Begrippen:** [ConfigMap](CONCEPTS.md#configmap) · [Secret](CONCEPTS.md#secret) · [Volumetypes](CONCEPTS.md#volumes)
- **L-09 — Resources en quota**
  - Pod met `limits.memory: 64Mi` die meer gebruikt (`busybox` met `sh -c "tail /dev/zero"`) → status `OOMKilled`.
  - `kubectl create quota mini --hard=pods=3,requests.cpu=1 --namespace=dev` en probeer een 4e Pod.
  - Een LimitRange die standaardwaarden zet; check met `kubectl describe pod`.

  🔗 **Begrippen:** [Requests en limits](CONCEPTS.md#requests-limits) · [ResourceQuota en LimitRange](CONCEPTS.md#resourcequota-limitrange)
- **L-10 — HPA (add-on: `metrics-server`)**
  ```bash
  kubectl autoscale deployment web --cpu-percent=50 --min=1 --max=5
  kubectl get hpa --watch      # genereer load met een busybox-Pod in een loop: wget -qO- http://web
  ```

  🔗 **Begrippen:** [HorizontalPodAutoscaler](CONCEPTS.md#hpa) · [metrics-server](CONCEPTS.md#metrics-server) · [Requests en limits](CONCEPTS.md#requests-limits)
- **L-11 — Scheduling**
  - `kubectl label node w1 disk=ssd` + nodeSelector; daarna hetzelfde met nodeAffinity (required vs preferred).
  - `kubectl taint node w2 dedicated=db:NoSchedule` → Pods mijden w2, behalve met een toleration. Weghalen: `kubectl taint node w2 dedicated=db:NoSchedule-`
  - DaemonSet maken via de dry-run-truc (Deployment-YAML → `kind: DaemonSet`, `replicas`/`strategy` weg).
  - Static Pod op w1: manifest in `/etc/kubernetes/manifests/` op w1 → verschijnt als `naam-w1`.
  - Topology spread: zet in een Deployment met 4 replicas `topologySpreadConstraints` met `maxSkew: 1` en
    `topologyKey: kubernetes.io/hostname`; vergelijk de verdeling met `kubectl get pods -o wide`.

  🔗 **Begrippen:** [nodeSelector en affinity](CONCEPTS.md#nodeselector-affinity) · [Taints en tolerations](CONCEPTS.md#taints-tolerations) · [DaemonSet](CONCEPTS.md#daemonset) · [Static Pods](CONCEPTS.md#static-pods) · [Labels en selectors](CONCEPTS.md#labels-selectors) · [Pod Topology Spread Constraints](CONCEPTS.md#topology-spread)
- **L-12 — Probes en command/args**
  - Liveness-probe die faalt → `kubectl describe pod` toont herstarts; readiness-probe die faalt → Pod verdwijnt uit de Service-endpoints.
  - `kubectl run t --image=busybox:1.36 --command -- sleep 3600` vs zonder `--command`: vergelijk `spec.containers[0].command` en `args`.
  - Voeg een `preStop`-hook (`sleep 10`) toe en kijk hoe lang `kubectl delete pod` duurt.

  🔗 **Begrippen:** [Probes (liveness, readiness, startup)](CONCEPTS.md#probes) · [command en args](CONCEPTS.md#command-args) · [Pod-levenscyclus, beëindiging en lifecycle hooks](CONCEPTS.md#pod-lifecycle)

- **L-34 — Init- en sidecar-containers**
  Een Pod met een init-container die wacht tot de Service `web` bestaat, en een native sidecar die het logbestand van de app volgt:
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata: {name: multi}
  spec:
    volumes: [{name: logs, emptyDir: {}}]
    initContainers:
    - name: wacht-op-web                       # init: moet eerst slagen
      image: busybox:1.36
      command: ["sh", "-c", "until nslookup web; do echo wacht; sleep 2; done"]
    - name: log-lezer                          # native sidecar: init + restartPolicy Always
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "touch /logs/app.log; tail -f /logs/app.log"]
      volumeMounts: [{name: logs, mountPath: /logs}]
    containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /logs/app.log; sleep 5; done"]
      volumeMounts: [{name: logs, mountPath: /logs}]
  ```
  `kubectl get pod multi --watch` (blijft op `Init:0/2` tot je `kubectl expose` of `create service` voor `web` doet), daarna
  `kubectl logs multi -c log-lezer`. Zie ook hoe de sidecar in `kubectl get pod multi -o yaml` staat.

  🔗 **Begrippen:** [Init-containers en sidecar-containers](CONCEPTS.md#init-sidecar) · [Pod-levenscyclus, beëindiging en lifecycle hooks](CONCEPTS.md#pod-lifecycle) · [Volumetypes](CONCEPTS.md#volumes) · [CoreDNS en Service-DNS](CONCEPTS.md#coredns)

- **L-35 — SecurityContext**
  ```bash
  kubectl run sec --image=busybox:1.36 --dry-run=client --output=yaml -- sleep 3600 > sec.yaml
  ```
  Voeg in `sec.yaml` toe: Pod-niveau `runAsUser: 1000`, `runAsNonRoot: true`; containerniveau `allowPrivilegeEscalation: false`,
  `readOnlyRootFilesystem: true`, `capabilities: {drop: [ALL]}`. Dan:
  ```bash
  kubectl apply -f sec.yaml && kubectl exec sec -- id && kubectl exec sec -- touch /test   # id = 1000; touch faalt (read-only)
  ```
  Haal `runAsUser` weg en zie wat `runAsNonRoot` doet met een image dat als root draait (`kubectl describe pod sec`).

  🔗 **Begrippen:** [SecurityContext](CONCEPTS.md#security-context) · [Pod](CONCEPTS.md#pod) · [Volumetypes](CONCEPTS.md#volumes)

- **L-36 — PodDisruptionBudget en drain**
  ```bash
  kubectl create deployment pdb-demo --image=nginx:1.27 --replicas=2
  kubectl create poddisruptionbudget pdb-demo --selector=app=pdb-demo --min-available=2
  kubectl drain w1 --ignore-daemonsets --timeout=30s     # faalt: zou de PDB schenden
  kubectl patch pdb pdb-demo --type=merge --patch='{"spec":{"minAvailable":1}}' && kubectl drain w1 --ignore-daemonsets
  kubectl uncordon w1
  ```

  🔗 **Begrippen:** [PodDisruptionBudget](CONCEPTS.md#pdb) · [Drain, cordon en uncordon](CONCEPTS.md#drain-cordon) · [Deployment en rolling updates](CONCEPTS.md#deployment)

Docs: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) ·
[HPA walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/) ·
[Taints](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) ·
[Assign Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
[Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) ·
[Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

---

## Blok 3 — Services & Networking (20%)

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 3 in CONCEPTS](CONCEPTS.md#blok-3)

- Connectiviteit tussen Pods (plat netwerk via CNI).
- Service-types: ClusterIP, NodePort, LoadBalancer, headless; Endpoints/EndpointSlices.
- NetworkPolicies: ingress/egress, pod-/namespace-selectors, default deny, DNS-egress toestaan.
- Ingress-controllers en Ingress-resources.
- Gateway API: GatewayClass, Gateway, HTTPRoute.
- CoreDNS: Service-DNS-namen (`svc.namespace.svc.cluster.local`), Corefile.
- Toegang zonder Service of Ingress: `kubectl port-forward` en `kubectl proxy`.

🔗 **Uitgewerkt in CONCEPTS:** [CNI: het Pod-netwerk](CONCEPTS.md#cni)

**Labs**
- **INIT §4** — CNI-rondes Flannel, Calico, Cilium, met de **NetworkPolicy-test**.
- **L-13 — Service-types**
  ```bash
  kubectl create deployment web --image=nginx:1.27 --replicas=2
  kubectl expose deployment web --port=80 --type=NodePort
  kubectl get service web --output=jsonpath='{.spec.ports[0].nodePort}'   # curl 192.168.122.12:<poort> vanaf aristotle
  kubectl get endpointslices --selector=kubernetes.io/service-name=web
  ```
  Daarna: een headless Service (`clusterIP: None`) en kijk wat DNS teruggeeft.
  Zonder Service-type testen: `kubectl port-forward service/web 8080:80 &` en `curl localhost:8080`.

  🔗 **Begrippen:** [Service](CONCEPTS.md#service) · [Endpoints en EndpointSlices](CONCEPTS.md#endpointslice) · [Toegang tot apps: port-forward en kubectl proxy](CONCEPTS.md#port-forward-proxy)
- **L-14 — CoreDNS**
  ```bash
  kubectl run dns --image=busybox:1.36 --rm --stdin --tty --restart=Never -- nslookup web.default.svc.cluster.local
  kubectl --namespace=kube-system get configmap coredns --output=yaml   # de Corefile
  ```

  🔗 **Begrippen:** [CoreDNS en Service-DNS](CONCEPTS.md#coredns) · [Service](CONCEPTS.md#service)
- **L-15 — NetworkPolicy verdieping** (snapshot `calico-ready`): alleen verkeer toestaan vanuit Pods met label
  `role=frontend`, daarna vanuit een andere namespace (namespaceSelector), en een egress-policy die alleen DNS (UDP/TCP 53) toestaat.

  🔗 **Begrippen:** [NetworkPolicy](CONCEPTS.md#networkpolicy) · [CNI: het Pod-netwerk](CONCEPTS.md#cni) · [Labels en selectors](CONCEPTS.md#labels-selectors)
- **L-16 — Ingress, Gateway API en LoadBalancer** (add-ons: `metallb gateway-crds helm traefik`)
  - `./addons.sh metallb` → `kubectl expose deployment web --port=80 --type=LoadBalancer --name=web-lb`
    krijgt een EXTERNAL-IP uit `192.168.122.200–250`; `curl` dat IP vanaf aristotle.
  - `./addons.sh gateway-crds helm traefik` → Traefik is je Ingress- én Gateway API-controller.
    (Ingress-NGINX is sinds maart 2026 met pensioen: geen releases of security-fixes meer.)
  - Ingress: `kubectl create ingress web --class=traefik --rule="web.lab/*=web:80"`, test met
    `curl -H 'Host: web.lab' http://<EXTERNAL-IP van service traefik>/`. Controleer de klassenaam met `kubectl get ingressclass`.
  - Gateway API: dezelfde route als `HTTPRoute` die naar de Gateway van Traefik verwijst (`kubectl get gateway --all-namespaces`).
    Voorbeelden: [gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/guides/getting-started/).

  🔗 **Begrippen:** [Ingress en ingress-controller](CONCEPTS.md#ingress) · [Gateway API](CONCEPTS.md#gateway-api) · [Service type LoadBalancer en MetalLB](CONCEPTS.md#loadbalancer)

Docs: [Service](https://kubernetes.io/docs/concepts/services-networking/service/) ·
[Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) ·
[DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) ·
[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) ·
[Gateway API (k8s)](https://kubernetes.io/docs/concepts/services-networking/gateway/) ·
[gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/) (toegestaan op het examen)

---

## Blok 4 — Storage (10%)

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 4 in CONCEPTS](CONCEPTS.md#blok-4)

- PersistentVolume vs PersistentVolumeClaim; binding.
- Access modes (RWO, ROX, RWX, RWOP) en reclaim policies (Retain, Delete).
- StorageClass en dynamische provisioning; `volumeBindingMode: WaitForFirstConsumer`.
- Volumetypes: emptyDir, hostPath, configMap/secret, PVC.
- PVC vergroten (`allowVolumeExpansion`), ephemeral volumes en local ephemeral storage.

**Labs**
- **L-17 — Statisch:** een PV met `hostPath` op w1 + een PVC die eraan bindt (let op `storageClassName`,
  grootte en access mode). Verwijder de PVC en kijk wat er met de PV gebeurt bij `Retain` vs `Delete`.
  Daarna een StorageClass zonder provisioner (`kubernetes.io/no-provisioner`) met `WaitForFirstConsumer`.

  🔗 **Begrippen:** [PersistentVolume en PersistentVolumeClaim](CONCEPTS.md#pv-pvc) · [Access modes en reclaim policy](CONCEPTS.md#access-modes-reclaim) · [Volumetypes](CONCEPTS.md#volumes)
- **L-18 — Dynamisch (add-on: `local-path`; `./addons.sh local-path` maakt hem meteen default):** PVC zonder PV → er wordt automatisch een PV gemaakt;
  zet de StorageClass als default en zie wat er met een PVC zonder `storageClassName` gebeurt.
  Vergroot de PVC (`kubectl patch pvc ... storage: 2Gi`) en lees de foutmelding als de StorageClass geen `allowVolumeExpansion` heeft.

  🔗 **Begrippen:** [StorageClass en dynamische provisioning](CONCEPTS.md#storageclass) · [PersistentVolume en PersistentVolumeClaim](CONCEPTS.md#pv-pvc) · [PVC vergroten en ephemeral volumes](CONCEPTS.md#volume-expansion-ephemeral)

Docs: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
[Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) ·
[Configure a Pod to use a PV](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)

---

## Blok 5 — Troubleshooting (30%)

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 5 in CONCEPTS](CONCEPTS.md#blok-5)

- Vaste aanpak: **status → events/logs → oorzaak → fix → verifiëren**.
- Clusters en nodes: NotReady, kubelet, containerd, certificaten.
- Control-plane-componenten: static-Pod-manifests, `crictl`, `/var/log/pods`.
- Resourcegebruik: `kubectl top`, events.
- Container-output: `kubectl logs` (ook `--previous`, `-c`).
- Services en netwerk: endpoints, selectors, targetPort, DNS, NetworkPolicies.
- `kubectl debug` (ephemeral containers, node-debug), waar logs op de node staan, node-pressure eviction.

**Labs** — met `./break.sh` (op aristotle): `./break.sh random` maakt iets kapot en toont alleen het symptoom;
`./break.sh check <nr>` controleert je oplossing; `./break.sh hint <nr>` geeft een hint (geen oplossing);
`./break.sh restore <nr>` is de noodknop. Overzicht: `./break.sh list`.

| L-lab | break.sh-scenario's |
|---|---|
| L-19 control plane | 1 (kubectl werkt niet), 4 (Pods blijven Pending) |
| L-20 applicaties | 5, 6, 7 |
| L-21 Services/DNS | 8, 9, 10 |
| L-22 nodes | 2, 3 |
- **INIT §3** — nodes NotReady door ontbrekende CNI.
- **INIT §5** — kapotte kubelet (`sudo systemctl stop kubelet` op w1).
- **L-19 — Kapotte control plane:** maak een typfout in `/etc/kubernetes/manifests/kube-apiserver.yaml` (bijv.
  een fout poortnummer). `kubectl` werkt niet meer → diagnose met `sudo crictl ps -a`, `sudo crictl logs <id>` en
  `/var/log/pods/`. Herstel en verifieer.

  🔗 **Begrippen:** [Static Pods](CONCEPTS.md#static-pods) · [crictl](CONCEPTS.md#crictl) · [kube-apiserver](CONCEPTS.md#kube-apiserver) · [Troubleshooting-aanpak](CONCEPTS.md#troubleshooting-methode)
- **L-20 — Kapotte applicaties:** maak één voor één: verkeerde image-tag (`ImagePullBackOff`), verkeerd `command`
  (`CrashLoopBackOff`), ontbrekende ConfigMap (`CreateContainerConfigError`), falende probe. Gebruik telkens
  `kubectl describe pod` (Events) en `kubectl logs --previous`.

  🔗 **Begrippen:** [Logs en events](CONCEPTS.md#logs-events) · [Pod](CONCEPTS.md#pod) · [command en args](CONCEPTS.md#command-args) · [Images, pull policy en private registries](CONCEPTS.md#images-pull) · [Pod-levenscyclus, beëindiging en lifecycle hooks](CONCEPTS.md#pod-lifecycle)
- **L-21 — Kapotte Service:** verkeerde selector of verkeerde `targetPort` → `kubectl get endpointslices` is leeg
  of verwijst naar de verkeerde poort. Herstel tot `curl` werkt.

  🔗 **Begrippen:** [Service](CONCEPTS.md#service) · [Endpoints en EndpointSlices](CONCEPTS.md#endpointslice) · [Labels en selectors](CONCEPTS.md#labels-selectors)
- **L-22 — Kapotte node-config:** foute waarde in `/var/lib/kubelet/config.yaml` of containerd gestopt op w2 →
  `journalctl --unit=kubelet --no-pager | tail` en `systemctl status containerd`.

  🔗 **Begrippen:** [kubelet](CONCEPTS.md#kubelet) · [Container runtime en CRI](CONCEPTS.md#container-runtime) · [Troubleshooting-aanpak](CONCEPTS.md#troubleshooting-methode) · [Node-pressure eviction](CONCEPTS.md#node-pressure-eviction) · [Logging-architectuur: waar staan de logs?](CONCEPTS.md#logging-architectuur)
- **L-23 — Monitoren (add-on: `metrics-server`):** `kubectl top nodes`, `kubectl top pods --sort-by=memory`,
  `kubectl get events --all-namespaces --sort-by=.lastTimestamp`.

  🔗 **Begrippen:** [metrics-server](CONCEPTS.md#metrics-server) · [Logs en events](CONCEPTS.md#logs-events)

- **L-37 — Debuggen zonder SSH en logs op de node**
  ```bash
  kubectl run stil --image=registry.k8s.io/pause:3.10           # image zonder shell
  kubectl exec -it stil -- sh                                   # faalt: geen shell in het image
  kubectl debug -it stil --image=busybox:1.36 --target=stil -- sh -c 'ps; ls /proc/1/root'   # ephemeral container
  kubectl debug node/w1 -it --image=busybox:1.36 -- chroot /host sh -c 'ls /var/log/pods | head; journalctl -u kubelet -n 5 --no-pager'
  kubectl get pods | grep node-debugger                          # opruimen: kubectl delete pod <naam>
  kubectl describe node w1 | grep -A6 Conditions                # MemoryPressure / DiskPressure / PIDPressure
  ```

  🔗 **Begrippen:** [kubectl debug: ephemeral containers en node-debugging](CONCEPTS.md#kubectl-debug) · [Logging-architectuur: waar staan de logs?](CONCEPTS.md#logging-architectuur) · [Node-pressure eviction](CONCEPTS.md#node-pressure-eviction) · [Troubleshooting-aanpak](CONCEPTS.md#troubleshooting-methode)

Docs: [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/) ·
[Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/) ·
[Debugging DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/) ·
[crictl](https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/) ·
[Debug nodes met kubectl](https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/)

---

## Blok 6 — Examentraining

- **killer.sh** — 2 simulatiesessies zitten bij je examen (elk 36 uur toegang, 17 vragen). Bewaar ze tot het
  einde van blok 5: ze zijn bewust zwaarder dan het examen. Doe de tweede pas als je de eerste helemaal hebt nagewerkt.
- **Killercoda** — gratis CKA-scenario's in de browser ([killercoda.com/killer-shell-cka](https://killercoda.com/killer-shell-cka)).
  Handig voor korte oefeningen tussendoor.
- **Toegestane documentatie** tijdens het examen: kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs en
  gateway-api.sigs.k8s.io. Oefen dus met álleen die bronnen, en leer waar de voorbeelden staan.
- **Examengewoontes:** elke vraag begint met een `kubectl config use-context`-commando: altijd uitvoeren. Sla
  zware vragen over en kom terug. Controleer elk antwoord (`kubectl get`, `describe`, een test-Pod).

**Optioneel, voor diep begrip (na het examen of als verdieping):** [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
— een cluster helemaal zonder kubeadm opbouwen (certificaten, etcd, control plane met de hand). Richt zich op
Kubernetes v1.32 en vraagt 4 machines; kan op je libvirt-host met 4 VM's.

---

## Blok 7 — Platform: GitOps en monitoring

Geen examenstof voor de CKA, wel dagelijkse praktijk en gespreksstof. Alles draait als gewone Pods in je
eigen cluster (open source, geen SaaS). Werk vanaf een eigen snapshot, zodat je CKA-labs schoon blijven:
`./snapshot.sh revert calico-ready` → labs hieronder → `./snapshot.sh save platform`.

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 7 in CONCEPTS](CONCEPTS.md#blok-7)

- **GitOps:** de gewenste toestand staat declaratief in git; een agent in het cluster haalt die op en houdt het
  cluster er continu gelijk aan (ook als iemand met de hand iets verandert: *drift*).
- **Argo CD:** GitOps-tool met web-UI. Een `Application` zegt: "deze map in deze repo hoort in deze namespace".
  Toont *Synced/OutOfSync* en *Healthy/Degraded* voor de resources die het beheert. De volledige set begrippen
  (reconciliatie, sync-policy, AppProject, ApplicationSet, hooks, SSO, ...) staat in
  [gitops-lab/CONCEPTS.md](../../gitops-lab/CONCEPTS.md).
- **Flux:** GitOps-tool zonder standaard-UI, opgebouwd uit controllers (bron ophalen → toepassen). Zelfde idee, andere bediening.
- **Monitoring vs metrics-server:** metrics-server geeft alleen actuele CPU/geheugen (voor `kubectl top`/HPA).
  Echte monitoring = metrics met historie, dashboards en alerts.
- **Prometheus** (metrics als tijdreeksen, haalt ze zelf op = *pull*), **Alertmanager** (alerts versturen),
  **Grafana** (dashboards), **kube-state-metrics** (status van Kubernetes-objecten), **node-exporter** (node-metrics).
- **kube-prometheus-stack:** één Helm-chart die dit allemaal installeert, inclusief kant-en-klare dashboards en alertregels.

**Labs**
- **G-01 t/m G-18 — GitOps met Argo CD** → [gitops-lab/LABS.md](../../gitops-lab/LABS.md)

  De Argo CD-labs zijn een eigen reeks geworden, met eigen begrippen en een eigen script. Argo CD draait als
  containers in **ditzelfde** cluster en leest de manifests uit deze repo, dus je oefent op je eigen omgeving:

  | Labs | Wat |
  |---|---|
  | [G-01](../../gitops-lab/LABS.md#g-01) | installeren, UI openen, CLI |
  | [G-02](../../gitops-lab/LABS.md#g-02) · [G-03](../../gitops-lab/LABS.md#g-03) | eerste Application, sync, drift, prune, selfHeal |
  | [G-04](../../gitops-lab/LABS.md#g-04) · [G-05](../../gitops-lab/LABS.md#g-05) | Kustomize-overlays en een Helm-bron |
  | [G-06](../../gitops-lab/LABS.md#g-06) · [G-07](../../gitops-lab/LABS.md#g-07) | sync waves, hooks (PreSync/PostSync/SyncFail) |
  | [G-08](../../gitops-lab/LABS.md#g-08) · [G-09](../../gitops-lab/LABS.md#g-09) | app-of-apps, ApplicationSet |
  | [G-10](../../gitops-lab/LABS.md#g-10) · [G-11](../../gitops-lab/LABS.md#g-11) | AppProject + sync-venster, RBAC + SSO via Dex |
  | [G-12](../../gitops-lab/LABS.md#g-12) · [G-13](../../gitops-lab/LABS.md#g-13) | notificaties, rollback en git revert |
  | [G-14](../../gitops-lab/LABS.md#g-14) · [G-15](../../gitops-lab/LABS.md#g-15) | ignoreDifferences, tweede cluster |
  | [G-16](../../gitops-lab/LABS.md#g-16) · [G-17](../../gitops-lab/LABS.md#g-17) | eigen health-check (Lua), image updater |
  | [G-18](../../gitops-lab/LABS.md#g-18) | disaster recovery: alles uit git opnieuw |

  ```bash
  cd ~/kubernetes/scripts/kubeadm-lab
  ./argocd.sh install      # Argo CD v3.5.6 + NodePort + argocd-CLI op cp1
  ./argocd.sh login
  ./argocd.sh bootstrap    # de root-Application: Argo CD neemt het over
  ```

  Zie ook [gitops-lab/README.md](../../gitops-lab/README.md) (snelstart) en
  [gitops-lab/SCRIPTS.md](../../gitops-lab/SCRIPTS.md) (wat het script onder water doet).

  🔗 **Begrippen:** [GitOps](../../gitops-lab/CONCEPTS.md#gitops) · [Applicatie](../../gitops-lab/CONCEPTS.md#applicatie) ·
  [Sync-policy](../../gitops-lab/CONCEPTS.md#sync-policy) · [Argo CD in de vault](CONCEPTS.md#argo-cd)
- **L-26 — Monitoring met kube-prometheus-stack** (Helm uit L-05 nodig)
  ```bash
  helm install mon oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
    --namespace=monitoring --create-namespace
  kubectl --namespace=monitoring get pods,services       # zoek de Grafana-service en het admin-secret
  kubectl --namespace=monitoring port-forward svc/mon-grafana 3000:80   # servicenaam controleren in de uitvoer hierboven
  ```
  - Bekijk in Grafana de dashboards voor nodes, Pods en namespaces.
  - Maak een Pod in CrashLoopBackOff (L-20) en kijk in Prometheus (Alerts) of de meegeleverde regel afgaat.
  - Vergelijk `kubectl top pods` (alleen nu) met Grafana (historie): dat is het verschil metrics-server vs monitoring.
  - **Daarna GitOps-stijl:** verwijder de Helm-release en installeer dezelfde chart opnieuw via een Argo CD-`Application`
    met een Helm-bron. Zo staat ook je monitoring in git.

  🔗 **Begrippen:** [Prometheus, Grafana en kube-prometheus-stack](CONCEPTS.md#prometheus-stack) · [Helm](CONCEPTS.md#helm)
- **L-27 — Flux ter vergelijking** (vanaf snapshot `calico-ready`, niet tegelijk met Argo CD op dezelfde apps)
  - Flux CLI installeren (de docs noemen o.a. yay voor Arch en een install-script; check daar de pakketnaam), daarna voor het lab `flux install`
    (zonder bootstrap; in productie gebruik je `flux bootstrap github`).
  - Dezelfde `apps/web/` uitrollen met een `GitRepository` + `Kustomization`, en de drift-test herhalen.
  - Vergelijk: Argo CD (UI, Applications) vs Flux (CLI, controllers, geen standaard-UI).

  🔗 **Begrippen:** [Flux](CONCEPTS.md#flux) · [Kustomize](CONCEPTS.md#kustomize) · [GitOps](CONCEPTS.md#gitops)

**Resources:** de monitoringstack vraagt meer geheugen; de workers staan daarom in `lab.env` op 4 GiB.

Docs: [Argo CD getting started](https://argo-cd.readthedocs.io/en/stable/getting_started/) ·
[Argo CD health](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) ·
[Flux installatie](https://fluxcd.io/flux/installation/) ·
[OpenGitOps-principes](https://opengitops.dev/) ·
[Prometheus overview](https://prometheus.io/docs/introduction/overview/) ·
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) ·
[metrics-server/Metrics API](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)

---

## Blok 8 — IaC en CI/CD: clusters en resources uitrollen

Geen examenstof voor de CKA, wel je dagelijkse werk en gespreksstof. Je rolt hier niet *in* een cluster uit,
maar het cluster zelf, met Terraform en GitHub Actions, in drie scenario's met hetzelfde model.

**Concepten**

🔗 **Alle begrippen van dit blok:** [Blok 8 in CONCEPTS](CONCEPTS.md#blok-8)

- **Het lagenmodel:** Terraform (push) voor infrastructuur en bootstrap, GitOps (pull) voor alles in het cluster.
- **Terraform:** providers, resources, data sources, `plan`/`apply`/`destroy`, modules (AVM); providerversies vastzetten.
- **State:** lokaal (lab) vs remote in Azure Storage met locking; state bevat secrets.
- **GitHub Actions:** workflows, jobs, runners, `permissions`, environments, `concurrency`.
- **Pull-request-flow:** plan op de PR als reviewmateriaal, apply na merge (eventueel met goedkeuring).
- **OIDC-federatie:** GitHub logt in bij Azure zonder secret; het subject moet exact kloppen.
- **Self-hosted runner:** voor netwerken waar GitHub niet bij kan (je libvirt-netwerk); nooit met een publieke repo.
- **AKS en AKS op Azure Local:** wat Azure overneemt ten opzichte van kubeadm.

| Scenario | Code | Workflow | Runner | Kosten |
|---|---|---|---|---|
| A. On-prem lab (aristotle) | [`iac/lab-libvirt/`](iac/lab-libvirt/README.md) | `lab-libvirt.yml` | self-hosted op aristotle | geen |
| B. AKS in Azure | [`iac/aks-azure/`](iac/aks-azure/README.md) | `aks-azure.yml` | GitHub (`ubuntu-latest`) | nodes zolang ze draaien: **destroy na afloop** |
| C. AKS op Azure Local | [`iac/aks-azurelocal/`](iac/aks-azurelocal/README.md) | alleen `terraform-checks.yml` (validate) | — | n.v.t. (geen toegang buiten werk) |

Eenmalige voorbereiding (repo, runner, Azure-bootstrap): [INIT](INIT.md), stap 8.

**Labs**
- **L-28 — Terraform met de hand (scenario A, zonder pipeline)** (op aristotle)
  Het Terraform-cluster heeft 3 × 4 GiB nodig. Zet het script-lab even uit (`virsh shutdown cp1` enz.) of verlaag het RAM
  in `terraform.tfvars` (zie het voorbeeldbestand).
  ```bash
  cd iac/lab-libvirt && cp terraform.tfvars.example terraform.tfvars    # vul je publieke key in
  terraform init -backend-config="path=$HOME/.local/state/kubeadm-lab-tf/terraform.tfstate"
  terraform plan                      # lees het plan: wat komt er, en waarom (pool, volumes, domains)?
  terraform apply && terraform output
  virsh list --all && virsh vol-list kubeadm-tf    # vergelijk met wat create-vms.sh maakt
  terraform plan                      # tweede keer: "No changes" (idempotent)
  virsh destroy tf-w2 && terraform plan   # zie wat Terraform van een met de hand gestopte VM vindt
  terraform destroy
  ```
  Kijk ook naar `terraform output -raw lab_env`: zo voeden de bestaande scripts zich met de Terraform-nodes.

  🔗 **Begrippen:** [Terraform](CONCEPTS.md#terraform) · [Terraform-state](CONCEPTS.md#terraform-state) · [Imperatief vs declaratief](CONCEPTS.md#imperatief-declaratief) · [Het lagenmodel](CONCEPTS.md#iac-lagen)
  📄 **Handleiding:** [iac/lab-libvirt/README.md](iac/lab-libvirt/README.md)

- **L-29 — Repo en CI (alleen controleren)**
  1. Zet deze map als **privé** repo op GitHub (INIT stap 8) en installeer de self-hosted runner.
  2. Maak een branch, verander iets kleins in `iac/lab-libvirt/variables.tf`, open een PR.
  3. Bekijk `terraform-checks` (fmt, validate, `bash -n`) en de `plan`-run van `lab-libvirt` op je runner.
  4. Maak met opzet een opmaakfout (verkeerde inspringing) en zie `terraform fmt -check` falen.

  🔗 **Begrippen:** [CI/CD-pipeline](CONCEPTS.md#ci-cd-pipeline) · [Self-hosted runner](CONCEPTS.md#self-hosted-runner) · [Pull-request-flow](CONCEPTS.md#pull-request-flow)
  📄 **Handleiding:** [iac/lab-libvirt/README.md](iac/lab-libvirt/README.md)

- **L-30 — Scenario A via de pipeline**
  1. Merge de PR uit L-29 → `lab-libvirt` doet apply en daarna kubeadm (`prep-nodes.sh`, `cp-init.sh`, `worker-join.sh` met `LAB_ENV`).
  2. `ssh ubuntu@192.168.122.21` → `kubectl get nodes`: een tweede cluster, NotReady tot je een CNI installeert (INIT stap 4).
  3. Voeg een node toe in `variables.tf` (`tf-w3`, .24) via een PR → na merge joint alleen die node (kubeadm init draait niet opnieuw).
  4. Opruimen: Actions → `lab-libvirt` → Run workflow → `destroy`.

  🔗 **Begrippen:** [Push vs pull](CONCEPTS.md#push-vs-pull) · [kubeadm join](CONCEPTS.md#kubeadm-join) · [Terraform-state](CONCEPTS.md#terraform-state)
  📄 **Handleiding:** [iac/lab-libvirt/README.md](iac/lab-libvirt/README.md)

- **L-31 — Scenario B: AKS met OIDC en Flux** (kosten: doe het in één sessie en ruim op)
  1. Eenmalig: `GH_REPO=<account>/<repo> ./iac/aks-azure/bootstrap.sh` en de variabelen in GitHub zetten (INIT stap 8).
  2. Gitops-repo (publiek, bijv. `k8s-lab-gitops` uit L-25): maak de map voor dit cluster:
     ```bash
     mkdir -p clusters/aks && printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nnamespace: web\nresources:\n  - namespace.yaml\n  - ../../apps/web\n' > clusters/aks/kustomization.yaml && printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: web\n' > clusters/aks/namespace.yaml
     ```
  3. PR in de lab-repo die iets in `iac/aks-azure/` raakt → lees het plan in de job summary → merge → keur de environment `azure` goed.
  4. `az aks get-credentials ...` (uit de job summary) → `kubectl get nodes`, `kubectl get pods --namespace=web`,
     `kubectl get gitrepositories,kustomizations.kustomize.toolkit.fluxcd.io --namespace=flux-system`.
  5. Wijzig `replicas` in de gitops-repo → binnen ± 2 minuten in AKS, **zonder** dat een workflow draait (pull).
  6. Vergelijk met je kubeadm-cluster: geen `/etc/kubernetes/manifests`, geen etcd-backup, LoadBalancer werkt zonder MetalLB.
  7. **Opruimen:** Actions → `aks-azure` → Run workflow → `destroy`. Controleer in de portal dat `rg-k8s-lab` leeg is
     (de `MC_...`-resource group verdwijnt met het cluster).

  🔗 **Begrippen:** [AKS](CONCEPTS.md#aks) · [OIDC-federatie](CONCEPTS.md#oidc-federatie) · [Pull-request-flow](CONCEPTS.md#pull-request-flow) · [Flux](CONCEPTS.md#flux) · [Terraform-state](CONCEPTS.md#terraform-state)
  📄 **Handleiding:** [iac/aks-azure/README.md](iac/aks-azure/README.md)

- **L-32 — Scenario C: AKS op Azure Local (lezen en vertalen naar je werk)**
  1. Lees `iac/aks-azurelocal/main.tf` naast `iac/aks-azure/main.tf`: wat is gelijk (Terraform, state, OIDC-pipeline), wat anders
     (custom location, logical network, control plane IP, providerversies)?
  2. Bekijk in `terraform-checks` dat scenario C wel gevalideerd wordt zonder Azure Local.
  3. Schrijf voor je werkomgeving op welke waarden je van de Azure Local-beheerder nodig hebt (zie `terraform.tfvars.example`)
     en welke rollen de pipeline-identiteit daar zou krijgen.
  4. Alleen waar het op je werk mag: plan uitvoeren tegen een testomgeving.

  🔗 **Begrippen:** [AKS op Azure Local](CONCEPTS.md#aks-arc) · [AKS](CONCEPTS.md#aks) · [Het lagenmodel](CONCEPTS.md#iac-lagen) · [Terraform](CONCEPTS.md#terraform)
  📄 **Handleiding:** [iac/aks-azurelocal/README.md](iac/aks-azurelocal/README.md)

Docs: [Terraform](https://developer.hashicorp.com/terraform/docs) ·
[libvirt-provider](https://github.com/dmacvicar/terraform-provider-libvirt) ·
[Backend azurerm](https://developer.hashicorp.com/terraform/language/backend/azurerm) ·
[GitHub OIDC in Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure) ·
[Self-hosted runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners) ·
[AKS system node pools](https://learn.microsoft.com/en-us/azure/aks/use-system-pools) ·
[Flux op AKS](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-gitops-flux2) ·
[AKS Arc met Terraform](https://learn.microsoft.com/en-us/azure/aks/aksarc/create-clusters-terraform)

---

## Blok 9 — Secret management: ESO en Azure Key Vault

Geen examenstof, wel het onderwerp waar de meeste incidenten en audits over gaan. Je leert secrets **buiten**
git houden en ze toch declaratief beheren: een vault als bron van waarheid, een operator in het cluster die
ze ophaalt, en git met alleen de verwijzing.

**Concepten**

🔗 **Alle begrippen van dit blok:** [secrets-lab/CONCEPTS.md](../../secrets-lab/CONCEPTS.md)

- **Waarom:** een Kubernetes Secret is base64, geen encryptie; in git zetten is definitief
  ([secret-hygiëne](../../secrets-lab/CONCEPTS.md#secret-hygiene)).
- **ESO:** `SecretStore`/`ClusterSecretStore` (hoe kom ik bij de vault), `ExternalSecret` (wat naar welk Secret),
  `PushSecret` (terug), `ClusterExternalSecret` (één definitie, veel namespaces).
- **Azure Key Vault:** RBAC versus access policies, purge protection (verplicht door policy in deze landing zone),
  private endpoints, en het verschil tussen secrets, keys en certificates.
- **Identiteit:** service principal met client-secret (dit lab) versus workload identity (op AKS, niet hier — de
  OIDC-issuer is niet publiek bereikbaar).
- **Alternatieven:** [OpenBao/Vault, Sealed Secrets, SOPS, CSI-driver, Keycloak (geen vault, wel een IdP)](../../secrets-lab/ALTERNATIVES.md).

**Labs** — volledige uitwerking in [secrets-lab/LABS.md](../../secrets-lab/LABS.md):

| Labs | Wat |
|---|---|
| [S-01](../../secrets-lab/LABS.md#s-01) · [S-02](../../secrets-lab/LABS.md#s-02) | base64 is geen encryptie; landing zone uit de vending machine |
| [S-03](../../secrets-lab/LABS.md#s-03) · [S-04](../../secrets-lab/LABS.md#s-04) | ESO installeren via Argo CD; eerste ExternalSecret |
| [S-05](../../secrets-lab/LABS.md#s-05) · [S-06](../../secrets-lab/LABS.md#s-06) | ordening (`CreateContainerConfigError`); `dataFrom` |
| [S-07](../../secrets-lab/LABS.md#s-07) · [S-08](../../secrets-lab/LABS.md#s-08) | templating; rotatie en refreshInterval |
| [S-09](../../secrets-lab/LABS.md#s-09) · [S-10](../../secrets-lab/LABS.md#s-10) | deletionPolicy; drift |
| [S-11](../../secrets-lab/LABS.md#s-11) · [S-12](../../secrets-lab/LABS.md#s-12) | ClusterExternalSecret; PushSecret |
| [S-13](../../secrets-lab/LABS.md#s-13) · [S-14](../../secrets-lab/LABS.md#s-14) | foutmodes; least privilege met twee identiteiten |
| [S-15](../../secrets-lab/LABS.md#s-15) · [S-16](../../secrets-lab/LABS.md#s-16) | workload identity (en waarom niet hier); CSI-driver |
| [S-17](../../secrets-lab/LABS.md#s-17) · [S-18](../../secrets-lab/LABS.md#s-18) | OpenBao; de ExternalSecret in Argo CD |
| [S-19](../../secrets-lab/LABS.md#s-19) · [S-20](../../secrets-lab/LABS.md#s-20) | monitoring; disaster recovery |

```bash
cd ~/kubernetes/scripts/kubeadm-lab
./secrets.sh install      # ESO via Argo CD
./secrets.sh azure init   # Key Vault + identiteiten + rollen
./secrets.sh azure seed   # voorbeeldsecrets
./secrets.sh stores       # SecretStore + ClusterSecretStore
./secrets.sh status
```

**Resources:** ESO vraagt weinig (3 kleine pods); de Key Vault kost per 10k operaties. De landing zone komt uit de
vending machine (`maxilabs/solutions`).

Docs: [External Secrets Operator](https://external-secrets.io/) ·
[Azure Key Vault-provider](https://external-secrets.io/latest/provider/azure-key-vault/) ·
[Key Vault RBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide) ·
[Workload identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview) ·
[OpenBao](https://openbao.org/)

---

## Curriculum-checklist (officiële competenties → labs)

| Competentie | Labs | Klaar |
|---|---|---|
| RBAC | L-04, L-33 | [ ] |
| Infrastructuur voorbereiden voor een cluster | INIT §2, node-prep.sh lezen | [ ] |
| Cluster maken en beheren met kubeadm | INIT §2, L-02, L-03 | [ ] |
| Cluster-lifecycle (upgrade) | INIT §5 | [ ] |
| HA control plane | concept + docs (optioneel lab later: cp2 + cp3 achter een HAProxy-VM, zie [HA-overwegingen](https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md); krap met 32 GB) | [ ] |
| Helm en Kustomize | L-05 | [ ] |
| Extensie-interfaces (CNI, CSI, CRI) | INIT §4, L-03, L-18 | [ ] |
| CRD's en operators | L-06, INIT §4B | [ ] |
| Deployments, rolling updates, rollbacks | L-07 | [ ] |
| ConfigMaps en Secrets | L-08 | [ ] |
| Workload-autoscaling | L-10 | [ ] |
| Zelfherstellende primitieven | L-07, L-11, L-12, L-34, L-36 | [ ] |
| Pod-admission en scheduling | L-09, L-11, L-35 | [ ] |
| Storage classes en dynamische provisioning | L-17, L-18 | [ ] |
| Volumetypes, access modes, reclaim policies | L-17, L-18 | [ ] |
| PV en PVC | L-17 | [ ] |
| Connectiviteit tussen Pods | INIT §4 | [ ] |
| NetworkPolicies | INIT NetworkPolicy-test, L-15 | [ ] |
| ClusterIP, NodePort, LoadBalancer, endpoints | L-13, L-16 | [ ] |
| Gateway API | L-16 | [ ] |
| Ingress-controllers en -resources | L-16 | [ ] |
| CoreDNS | L-14 | [ ] |
| Clusters en nodes troubleshooten | INIT §3, §5, L-22, L-37 | [ ] |
| Clustercomponenten troubleshooten | L-19 | [ ] |
| Resourcegebruik monitoren | L-23 | [ ] |
| Container-output beheren en beoordelen | L-20, L-37 | [ ] |
| Services en netwerk troubleshooten | L-21, L-14 | [ ] |

---

## Na de CKA: Kubestronaut-traject

Dit bestand is leidend voor de inhoud (blokken, labs, begrippen). Het overzicht over alle certificeringen heen
en je voortgang houd je bij in STUDYPATH. Focus nu op de CKA;
onderstaande certificeringen zijn de vervolgstappen.

| Volgorde | Certificering | Type | Duur | K8s-versie | Geldig | Vereiste | Status |
|---|---|---|---|---|---|---|---|
| 1 | **CKA** | Praktijk | 2 uur | v1.35 | 2 jaar | — | [ ] |
| 2 | CKAD | Praktijk | 2 uur | v1.37 | 2 jaar | — | [ ] |
| 3 | KCSA | Meerkeuze | 90 min | — | 2 jaar | — | [ ] |
| 4 | CKS | Praktijk | 2 uur | v1.35 | 2 jaar | **Geldige CKA** | [ ] |
| 5 | KCNA | Meerkeuze | 90 min | — | 2 jaar | — | [ ] |

- **Kubestronaut** = alle vijf behaald én tegelijk geldig. Met 2 jaar geldigheid per certificering moet het hele
  traject binnen die termijn passen.
- CKAD draait op **v1.37**: upgrade je lab dan door (1.35 → 1.36 → 1.37), meteen extra upgrade-oefening.
- Golden Kubestronaut (alle CNCF-certificeringen + LFCS) valt buiten dit plan.
- Alle begrippen die vooral voor CKAD en CKS zijn: [Kubestronaut in CONCEPTS](CONCEPTS.md#blok-ks).

### CKAD (applicatiekant; grote overlap met CKA blok 2–3)
🔗 **Begrippen:** [Downward API en projected volumes](CONCEPTS.md#downward-api) · [Vertical Pod Autoscaler en in-place resize](CONCEPTS.md#vpa-inplace-resize) · [API-groepen, versies en deprecaties](CONCEPTS.md#api-versies) · [Init-containers en sidecar-containers](CONCEPTS.md#init-sidecar) · [SecurityContext](CONCEPTS.md#security-context) · [Pod Security Standards en Pod Security Admission](CONCEPTS.md#pod-security-admission)

| Domein | Gewicht | Kern | Labs | Klaar |
|---|---|---|---|---|
| Application Design and Build | 20% | images bouwen, workloadkeuze, sidecar/init-containers, volumes | L-07, L-12 + image bouwen met podman op aristotle | [ ] |
| Application Deployment | 20% | blue/green, canary, rolling updates, Helm, Kustomize | L-05, L-07, L-25 | [ ] |
| Application Observability and Maintenance | 15% | API-deprecaties, probes, CLI-monitoring, logs, debuggen | L-12, L-20, L-23 | [ ] |
| Application Environment, Configuration and Security | 25% | CRD's/operators, authN/authZ/admission, quota, ConfigMaps/Secrets, ServiceAccounts, SecurityContext | L-04, L-06, L-08, L-09 | [ ] |
| Services and Networking | 20% | NetworkPolicies, Services, Ingress | L-13, L-15, L-16 | [ ] |

### CKS (security; vereist een geldige CKA)
🔗 **Begrippen:** [Pod Security Standards en Pod Security Admission](CONCEPTS.md#pod-security-admission) · [Admission control: controllers, policies en webhooks](CONCEPTS.md#admission-control) · [Encryption at rest en KMS](CONCEPTS.md#encryption-at-rest) · [Audit logging](CONCEPTS.md#audit-logging) · [SecurityContext](CONCEPTS.md#security-context) · [Gebruikers en certificaten via de CSR-API](CONCEPTS.md#csr-gebruikers)

| Domein | Gewicht | Kern | Lab-richting (tools verifiëren zodra CKS aan de beurt is) | Klaar |
|---|---|---|---|---|
| Cluster Setup | 15% | network policies, CIS-benchmarks, Ingress met TLS, node-metadata, binaries verifiëren | kube-bench, Ingress + TLS | [ ] |
| Cluster Hardening | 15% | RBAC minimaliseren, ServiceAccounts beperken, API-toegang, upgraden | L-04 verdiept, upgrade | [ ] |
| System Hardening | 10% | host minimaliseren, least privilege, netwerk beperken, AppArmor/seccomp | AppArmor- en seccomp-profielen | [ ] |
| Minimize Microservice Vulnerabilities | 20% | Pod Security Standards, Secrets, isolatie (sandboxed containers), pod-to-pod-encryptie | PSA per namespace, RuntimeClass met gVisor (`runsc`), Cilium (ronde C) | [ ] |
| Supply Chain Security | 20% | minimale images, SBOM, registries, signeren, statische analyse | Trivy (scan + SBOM), image signing, Kubesec en KubeLinter (statische analyse van manifests) | [ ] |
| Monitoring, Logging and Runtime Security | 20% | gedragsanalyse, dreigingsdetectie, immutability, audit logs | Falco, audit-policy, `readOnlyRootFilesystem` | [ ] |

### KCSA (meerkeuze; opstap naar CKS)
| Domein | Gewicht | Klaar |
|---|---|---|
| Kubernetes Cluster Component Security | 22% | [ ] |
| Kubernetes Security Fundamentals | 22% | [ ] |
| Kubernetes Threat Model | 16% | [ ] |
| Platform Security | 16% | [ ] |
| Overview of Cloud Native Security | 14% | [ ] |
| Compliance and Security Frameworks | 10% | [ ] |

### KCNA (meerkeuze; grotendeels gedekt door de CKA)
| Domein | Gewicht | Klaar |
|---|---|---|
| Kubernetes Fundamentals | 44% | [ ] |
| Container Orchestration | 28% | [ ] |
| Cloud Native Application Delivery | 16% | [ ] |
| Cloud Native Architecture | 12% | [ ] |

## Bewust niet behandeld

De volledige inhoudsopgave van kubernetes.io/docs is op 15-10-2026 doorgelopen. Deze onderwerpen staan er wel, maar vallen
buiten de CKA, het Kubestronaut-traject en je werk, of zijn nog in ontwikkeling. Bewust weggelaten, niet vergeten:

| Onderwerp | Waarom niet |
|---|---|
| Windows-nodes en Windows-containers | geen examenstof, niet in je omgeving |
| Dynamic Resource Allocation, GPU's, hugepages, device plugins | gespecialiseerde hardware (AI/HPC) |
| Workload API, PodGroup en gang scheduling | nieuw, voor AI- en batchworkloads; nog in ontwikkeling |
| IPv4/IPv6 dual-stack, ServiceCIDR uitbreiden | randgeval voor netwerkbeheer |
| API Priority and Fairness, scheduling-framework, meerdere schedulers | internals voor grote clusters |
| Aggregation layer, Konnectivity, extension API servers | zeldzaam; CRD's dekken bijna alle uitbreidingen |
| User namespaces (stable vanaf 1.36) | relevant voor CKS-verdieping later; nu niet |

Komt een van deze toch terug in een examen of op je werk, dan wordt het eerst een stub in CONCEPTS en daarna uitgewerkt.

## Bronnen
- Kubestronaut-programma: https://www.cncf.io/training/kubestronaut
- CKAD: https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/
- CKS: https://training.linuxfoundation.org/certification/certified-kubernetes-security-specialist/
- KCSA: https://training.linuxfoundation.org/certification/kubernetes-and-cloud-native-security-associate-kcsa/
- KCNA: https://training.linuxfoundation.org/certification/kubernetes-cloud-native-associate/
- CKA-domeinen en competenties: https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/
- Toegestane bronnen tijdens het examen: https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed
- Killercoda CKA: https://killercoda.com/killer-shell-cka
- Kubernetes The Hard Way: https://github.com/kelseyhightower/kubernetes-the-hard-way
- Alle overige links staan per blok hierboven (kubernetes.io).
