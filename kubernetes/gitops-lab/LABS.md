# LABS — GitOps met Argo CD, van eerste sync tot disaster recovery

Elk lab heeft dezelfde vorm: **doel → stappen → verificatie → begrippen**. De begrippen staan in
[CONCEPTS](CONCEPTS.md); de commando's komen uit `../scripts/kubeadm-lab/argocd.sh` en de manifests uit deze map.

**Uitgangspunt:** je werkt vanaf **aristotle** in `~/kubernetes/scripts/kubeadm-lab` (dat is de map met de
scripts). `~/kubernetes` is een symlink naar `kubernetes/` in de repo `maxilabs/training`, dus je commits gaan
naar dezelfde repo die Argo CD leest.

```bash
cd ~/kubernetes/scripts/kubeadm-lab
./argocd.sh install          # alleen de eerste keer
./argocd.sh login
```

**Volgorde:** G-01 t/m G-03 bouwen met de hand op, G-04 t/m G-07 voegen stukjes toe, G-08 zet daarna alles op
GitOps-manier klaar (app-of-apps), G-09 t/m G-17 zijn losse concepten en G-18 breekt alles af en bouwt het terug.
Na elk blok: `./argocd.sh reset` als je schoon wilt beginnen (Argo CD blijft staan).

---

## g-01

### G-01 — Argo CD installeren en de UI openen

**Doel:** Argo CD als containers in je cluster, met een UI die je vanaf aristotle kunt openen, en de CLI op cp1.

**Stappen**
```bash
cd ~/kubernetes/scripts/kubeadm-lab
./argocd.sh install
```

Wat het script doet (zie [SCRIPTS](../scripts/kubeadm-lab/SCRIPTS.md)):
1. namespace `argocd`;
2. de officiële `install.yaml` van **v3.5.6** met `--server-side` (de CRD's zijn te groot voor een gewone apply);
3. wachten tot alle zeven componenten draaien;
4. de Service `argocd-server` als **NodePort** (443 → 30443), zodat je geen ssh-tunnel nodig hebt;
5. de `argocd`-CLI op cp1.

**Verificatie**
```bash
./argocd.sh status                 # 7 pods Running, verder nog geen Applications
./argocd.sh url                    # https://192.168.122.11:30443
./argocd.sh password               # admin-wachtwoord
curl -sk "$(./argocd.sh url)/api/version"   # {"Version":"v3.5.6"}
```
Open de URL in je browser (self-signed certificaat: accepteren) en log in als `admin`.

**Waarom geen ssh-tunnel?** Dat kan ook (`kubectl port-forward svc/argocd-server 8080:443`), maar een NodePort
werkt vanuit je hele lab-netwerk en is wat je in een echt cluster ook zou overwegen.

**Valkuilen**
- `install.yaml` zonder `--server-side` geeft `metadata.annotations: Too long`. Dat is geen fout in je YAML.
- Het admin-wachtwoord staat in `argocd-initial-admin-secret`. In productie: wijzigen en dat secret verwijderen.

🔗 **Begrippen:** [Argo CD-architectuur](CONCEPTS.md#argo-architectuur) · [Applicatie](CONCEPTS.md#applicatie)

---

## g-02

### G-02 — Je eerste Application: van OutOfSync naar Synced

**Doel:** Eén Application met de hand maken, het verschil zien, en zelf syncen. Nog geen automatiek.

**Stappen**
```bash
cd ~/kubernetes/scripts/kubeadm-lab
./argocd.sh reset     # schone lei: geen apps, geen lab-namespaces

# De Application is een gewoon Kubernetes-object:
cat <<'EOF' | ssh -o StrictHostKeyChecking=accept-new ubuntu@192.168.122.11 "kubectl apply --filename=-"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-lab
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/maxilabs/training.git
    targetRevision: main
    path: kubernetes/gitops-lab/workloads/web/overlays/lab
  destination:
    server: https://kubernetes.default.svc
    namespace: web-lab
  syncOptions:
    - CreateNamespace=true
EOF
```
> Korter kan ook: `argocd app create web-lab --repo ... --path ... --dest-server ... --dest-namespace web-lab`,
> maar dan staat je app niet in git. Doe het déclaratief, dat is het hele punt.

**Verificatie**
```bash
./argocd.sh login
ssh ubuntu@192.168.122.11 'argocd app get web-lab'    # Sync Status: OutOfSync
ssh ubuntu@192.168.122.11 'argocd app diff web-lab'   # de diff is je hele app
ssh ubuntu@192.168.122.11 'argocd app sync web-lab'
ssh ubuntu@192.168.122.11 'argocd app get web-lab'    # Synced + Healthy
```
In de UI zie je de resource-boom: Namespace → Deployment/Service/ConfigMap.

**Valkuilen**
- `project: default` is nu genoeg; in G-10 maken we een eigen project.
- Zonder `CreateNamespace=true` faalt de sync met "namespace not found" — de namespace staat niet in je mappen.

🔗 **Begrippen:** [Applicatie](CONCEPTS.md#applicatie) · [Sync](CONCEPTS.md#sync) ·
[Gewenste vs live toestand](CONCEPTS.md#desired-vs-live) · [Sync-status](CONCEPTS.md#sync-status)

---

## g-03

### G-03 — Automated sync, prune en selfHeal (drift)

**Doel:** Git de baas maken: automatisch syncen, verwijderde resources opruimen, en handmatige wijzigingen
terugdraaien.

**Stappen**

1. Zet automatiek aan (in de Application uit G-02):
```bash
ssh ubuntu@192.168.122.11 "argocd app set web-lab --sync-policy automated --auto-prune --self-heal"
```
2. **Drift:** schaal de Deployment met de hand terug.
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=web-lab scale deployment web --replicas=1'
sleep 30
ssh ubuntu@192.168.122.11 'kubectl --namespace=web-lab get deployment web -o jsonpath="{.spec.replicas}"; echo'
```
3. **Wijziging via git:** pas de tekst in de overlay aan.
```bash
cd ~/kubernetes/gitops-lab/workloads/web/overlays/lab
sed -i 's/Deze tekst staat in git/Deze tekst komt uit een commit/' index.html
git -C ~/kubernetes commit -am "web-lab: tekst gewijzigd" && git -C ~/kubernetes push
```
4. **Prune:** voeg tijdelijk een resource toe en haal hem weer weg.
```bash
cd ~/kubernetes/gitops-lab/workloads/web/base
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: tijdelijk\ndata:\n  x: "1"\n' > tijdelijk.yaml
sed -i 's/  - configmap.yaml/  - configmap.yaml\n  - tijdelijk.yaml/' kustomization.yaml
git -C ~/kubernetes commit -am "tijdelijk" && git -C ~/kubernetes push
# ... wachten tot hij bestaat, dan:
rm tijdelijk.yaml && git -C ~/kubernetes commit -am "tijdelijk weg" && git -C ~/kubernetes push
```

**Verificatie**
- Stap 2: de replicas zijn binnen ~10-30 seconden weer `2` — en de app was even `OutOfSync`.
- Stap 3: binnen 3 minuten (polling) staat de nieuwe tekst in de Pod:
  `kubectl --namespace=web-lab exec deploy/web -- wget -qO- http://localhost/`.
- Stap 4: de ConfigMap `tijdelijk` verdwijnt na de tweede push. Dat is `prune`.

**Sneller dan 3 minuten?** `argocd app get web-lab --refresh` forceert een vergelijking. Zie
[webhooks vs polling](CONCEPTS.md#webhooks-vs-polling) voor waarom een webhook hier niet kan.

**Valkuilen**
- Zonder `selfHeal` blijft de app `OutOfSync` staan en gebeurt er niets met je `kubectl scale`.
- `prune` kijkt alleen naar wat de app zélf heeft aangemaakt ([resource tracking](CONCEPTS.md#resource-tracking)).

🔗 **Begrippen:** [Sync-policy](CONCEPTS.md#sync-policy) · [Drift](CONCEPTS.md#drift) · [Prune](CONCEPTS.md#prune) ·
[Drift in de hoofdvault](../scripts/kubeadm-lab/CONCEPTS.md#imperatief-declaratief)

---

## g-04

### G-04 — Kustomize: één base, twee omgevingen

**Doel:** Dezelfde workload in `web-lab` (2 replica's) en `web-prod` (3 replica's) uit één base.

**Stappen**
1. Bekijk de structuur: `workloads/web/base` (Deployment, Service, ConfigMap) en de overlays
   `overlays/lab` en `overlays/prod` (elk met een eigen `index.html`, `namespace` en `replicas`).
2. Maak de tweede omgeving als Application (declaratief, zoals in G-02):
```bash
cat <<'EOF' | ssh ubuntu@192.168.122.11 "kubectl apply --filename=-"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/maxilabs/training.git
    targetRevision: main
    path: kubernetes/gitops-lab/workloads/web/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: web-prod
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
EOF
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'argocd app manifests web-lab | head -40'   # de gerenderde YAML
ssh ubuntu@192.168.122.11 'kubectl --namespace=web-lab get deploy web -o jsonpath="{.spec.replicas}"; echo'
ssh ubuntu@192.168.122.11 'kubectl --namespace=web-prod get deploy web -o jsonpath="{.spec.replicas}"; echo'
```
2 en 3 — uit dezelfde base. Dat is [omgevingspromotie](CONCEPTS.md#omgevingspromotie).

**Valkuilen**
- De `configMapGenerator` geeft de ConfigMap een hash-suffix. Daardoor rollen de Pods netjes opnieuw bij een
  tekstwijziging. Een "gewone" ConfigMap doet dat niet.

🔗 **Begrippen:** [Kustomize als bron](CONCEPTS.md#kustomize-in-argo) · [Omgevingspromotie](CONCEPTS.md#omgevingspromotie) ·
[Kustomize in de hoofdvault](../scripts/kubeadm-lab/CONCEPTS.md#kustomize)

---

## g-05

### G-05 — Helm als bron: values en parameters

**Doel:** Een chart uit de repo laten renderen door Argo CD, met de voorrang van `values.yaml` →
`values-lab.yaml` → `parameters`.

**Stappen**
1. Bekijk de chart: `workloads/helm-demo` (`Chart.yaml`, `values.yaml`, `values-lab.yaml`, `templates/`).
2. Maak de Application:
```bash
cat <<'EOF' | ssh ubuntu@192.168.122.11 "kubectl apply --filename=-"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: helm-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/maxilabs/training.git
    targetRevision: main
    path: kubernetes/gitops-lab/workloads/helm-demo
    helm:
      releaseName: helm-demo
      valueFiles: [values-lab.yaml]
      parameters:
        - name: message
          value: "parameters winnen van valueFiles"
  destination:
    server: https://kubernetes.default.svc
    namespace: helm-demo
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
EOF
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=helm-demo get deploy,pods'
ssh ubuntu@192.168.122.11 'kubectl --namespace=helm-demo exec deploy/helm-demo -- wget -qO- http://localhost/'
```
Je ziet de tekst uit `parameters` (2 replica's uit `values-lab.yaml`, 1 zou uit `values.yaml` komen).

**Valkuilen**
- Argo CD installeert de chart zelf; er is **geen** Helm-release-secret in het cluster. `helm list` op de node
  laat dus niets zien. Dat is geen fout.
- Verkeerde indentatie in een template geeft een renderfout in de repo-server, niet in je editor.

🔗 **Begrippen:** [Helm als bron](CONCEPTS.md#helm-in-argo) · [Repo-server](CONCEPTS.md#repo-server) ·
[Helm in de hoofdvault](../scripts/kubeadm-lab/CONCEPTS.md#helm)

---

## g-06

### G-06 — Sync waves: volgorde in één sync

**Doel:** Zien dat Argo CD resources in golven toepast en per golf op gezondheid wacht.

**Stappen**
```bash
cat <<'EOF' | ssh ubuntu@192.168.122.11 "kubectl apply --filename=-"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: waves
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/maxilabs/training.git
    targetRevision: main
    path: kubernetes/gitops-lab/workloads/waves
  destination:
    server: https://kubernetes.default.svc
    namespace: lab-waves
EOF
ssh ubuntu@192.168.122.11 'argocd app sync waves'
```

De annotaties in `workloads/waves`:
| Golf | Resource |
|---|---|
| -3 | Namespace `lab-waves` |
| -2 | ConfigMap `waves-html` |
| 0 | Deployment + Service |
| hook | PreSync- en PostSync-Job (zie G-07) |

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'argocd app get waves'
ssh ubuntu@192.168.122.11 'kubectl --namespace=lab-waves logs job/waves-postsync'
```
De PostSync-hook doet `wget` naar de Service en print de HTML. Dat kan alleen als de Pod écht Ready was: bewijs
dat de hook ná de health-check van golf 0 draait.

**Valkuilen**
- Zonder golven is de volgorde binnen een map niet gegarandeerd. Het staat "toevallig" goed en valt om bij schaal.
- Een golf wacht op *health*; een CRD zonder health-check is meteen klaar (zie G-16).

🔗 **Begrippen:** [Sync waves](CONCEPTS.md#sync-waves) · [Health-status](CONCEPTS.md#health-status) ·
[Hooks](CONCEPTS.md#hooks)

---

## g-07

### G-07 — Hooks: PreSync, PostSync en een falende sync

**Doel:** Een mislukte sync laten gebeuren en begrijpen wat er dan wél en níet uitgerold wordt.

**Stappen**
1. Maak de app die met opzet faalt (staat expres buiten de root-app):
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/gitops-lab/clusters/lab/optional/waves-fail.yaml
```
2. Sync hem met de hand (de app heeft bewust géén `automated`):
```bash
ssh ubuntu@192.168.122.11 'argocd app sync waves-fail'
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=lab-waves-fail get jobs,pods'
ssh ubuntu@192.168.122.11 'kubectl --namespace=lab-waves-fail logs job/fail-syncfail'
ssh ubuntu@192.168.122.11 'kubectl --namespace=lab-waves-fail get deploy'   # bestaat niet
```
- `fail-presync` is `Failed` → de sync stopt bij de eerste hook.
- `fail-syncfail` is `Complete` → de SyncFail-hook draaide.
- De Deployment is **niet** aangemaakt: dat is het bewijs dat PreSync vóór de workloads gaat.

**De lus die je moet kennen:** zet `automated` aan op een app met een falende hook en Argo CD blijft proberen
("Retrying attempt #n"). Stoppen:
```bash
ssh ubuntu@192.168.122.11 'argocd app terminate-op waves-fail'
```

**Valkuilen**
- Hooks zijn geen gewone resources: je ziet ze niet in de resource-boom als eigenaar van de app.
- `hook-delete-policy: BeforeHookCreation` voorkomt naamconflicten bij de volgende sync.

🔗 **Begrippen:** [Hooks](CONCEPTS.md#hooks) · [Reconciliatie](CONCEPTS.md#reconciliatie) ·
[Job en CronJob in de hoofdvault](../scripts/kubeadm-lab/CONCEPTS.md#job-cronjob)

---

## g-08

### G-08 — App-of-apps: Argo CD neemt het over

**Doel:** Van handmatige Applications naar één root-Application die de rest uit git beheert — inclusief Argo CD's
eigen configuratie.

**Stappen**
1. Ruim je handgemaakte apps op:
```bash
./argocd.sh reset
```
2. Pas de root-Application toe:
```bash
./argocd.sh bootstrap
```
3. Kijk wat er ontstaat:
```bash
./argocd.sh status
ssh ubuntu@192.168.122.11 'argocd app tree root'
```

**Verificatie**

| Application | Beheert |
|---|---|
| `root` | de map `clusters/lab/apps` (de andere Applications) |
| `platform` | AppProject `lab`, `argocd-rbac-cm`, `argocd-notifications-cm` |
| `echo-receiver` | de webhook-ontvanger voor notificaties |
| `web-lab`, `web-prod` | de twee Kustomize-overlays |
| `helm-demo` | de Helm-chart |
| `waves` | golven en hooks |
| `guests-*` | gemaakt door de ApplicationSet (G-09) |

Alles `Synced` + `Healthy`. Vanaf nu: **niets meer met `kubectl` of `argocd app create`**, alleen git.

**Valkuilen**
- De root-app is je single point of failure: `kubectl delete application root` met cascade haalt alles weg.
- De sync-wave-annotatie op de Applications (`platform` = -10) zorgt dat het project bestaat vóór de apps die het
  gebruiken.

🔗 **Begrippen:** [App-of-apps](CONCEPTS.md#app-of-apps) · [Argo CD beheert zichzelf](CONCEPTS.md#self-management) ·
[AppProject](CONCEPTS.md#appproject)

---

## g-09

### G-09 — ApplicationSet: apps genereren uit mappen

**Doel:** Drie omgevingen uit één CR, en een vierde toevoegen met alleen een map.

**Stappen**
1. Bekijk `clusters/lab/apps/guests-appset.yaml`: een **git-files-generator** leest
   `workloads/guests/*/config.yaml` en maakt per bestand een Application.
2. Voeg een omgeving toe:
```bash
cd ~/kubernetes/gitops-lab/workloads/guests
mkdir -p acc && cd acc
cp ../dev/index.html . && sed -i 's/dev/acceptatie/' index.html
cat > config.yaml <<'EOF'
name: guests-acc
namespace: guests-acc
sourcePath: kubernetes/gitops-lab/workloads/guests/acc
EOF
sed 's/guests-dev/guests-acc/' ../dev/kustomization.yaml > kustomization.yaml
git -C ~/kubernetes add . && git -C ~/kubernetes commit -m "guests: acceptatie-omgeving" && git -C ~/kubernetes push
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'argocd app list | grep guests'
ssh ubuntu@192.168.122.11 'kubectl --namespace=guests-acc get deploy,pods'
```
Vier apps, zonder dat je er één met de hand hebt gemaakt. Verwijder de map (`git rm -r`): de Application verdwijnt
en met `prune` ook de resources.

**Valkuilen**
- `goTemplate: true` betekent `{{ .naam }}` met spaties; zonder die optie is het `{{naam}}`.
- De generator leest alleen de paden die je opgeeft. Een `config.yaml` buiten dat patroon doet niets.
- Een ApplicationSet is geen eigenaar in Kubernetes-zin: kinderen verdwijnen mee.

🔗 **Begrippen:** [ApplicationSet](CONCEPTS.md#applicationset) · [Applicatie](CONCEPTS.md#applicatie) ·
[Omgevingspromotie](CONCEPTS.md#omgevingspromotie)

---

## g-10

### G-10 — AppProject: de grens, en een sync-venster

**Doel:** Voelen dat een project een harde grens is, niet een documentatie-regel.

**Stappen**
1. Bekijk `platform/project.yaml`: alleen repo `maxilabs/training`, alleen namespaces `web-*`, `guests-*`,
   `lab-*`, `helm-demo`, `multi-lab`; cluster-scoped alleen Namespace en CRD.
2. **Grens testen** (buiten het project om):
```bash
cat <<'EOF' | ssh ubuntu@192.168.122.11 "kubectl apply --filename=-"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: buiten-de-grens, namespace: argocd}
spec:
  project: lab
  source:
    repoURL: https://github.com/maxilabs/training.git
    targetRevision: main
    path: kubernetes/gitops-lab/workloads/waves
  destination: {server: https://kubernetes.default.svc, namespace: kube-system}
EOF
ssh ubuntu@192.168.122.11 'argocd app sync buiten-de-grens'
```
3. **Sync-venster testen:** zet in `platform/project.yaml` de schedule tijdelijk op `"* * * * *"`, commit, push,
   en probeer te syncen.
```bash
ssh ubuntu@192.168.122.11 'argocd app sync web-lab'
```

**Verificatie**
- Stap 2: de app krijgt meteen `InvalidSpecError`:
  `application destination server '...' and namespace 'kube-system' do not match any of the allowed destinations
  in project 'lab'`. De sync gebeurt dus niet — geen enkele resource wordt aangeraakt. (Opruimen:
  `argocd app delete buiten-de-grens --cascade=orphan`.)
- Stap 3: `cannot sync: blocked by sync window`. Zet de schedule terug en push; de app herstelt zichzelf.

**Valkuilen**
- `manualSync: false` in een **deny**-venster betekent: ook handmatig syncen wordt geweigerd. `true` is de
  noodgreep waarmee jij er alsnog doorheen mag.
- `CreateNamespace=true` heeft een Namespace-regel in `clusterResourceWhitelist` nodig. En een eigen CRD heeft een
  CRD-regel nodig — dat is precies waar G-16 in eerste instantie op stukliep.

🔗 **Begrippen:** [AppProject](CONCEPTS.md#appproject) · [Sync windows](CONCEPTS.md#sync-windows) ·
[RBAC in de hoofdvault](../scripts/kubeadm-lab/CONCEPTS.md#rbac)

---

## g-11

### G-11 — RBAC en SSO via Dex

**Doel:** Inloggen met een SSO-gebruiker in plaats van `admin`, en merken dat rechten echt afgedwongen worden.

**Stappen**
1. SSO aanzetten (Dex met één lokale gebruiker, zodat je geen externe IdP nodig hebt):
```bash
./argocd.sh sso enable
```
Het script zet `url` + `dex.config` in `argocd-cm`, herstart de server en Dex, en controleert met een echte login.
2. Log in de UI in met **`student@lab.local` / `lab-wachtwoord`** (knop "Log in via Dex").
3. Bekijk de RBAC in git: `platform/rbac-cm.yaml`.
4. **Rechten testen:** verander in git de mapping naar `role:readonly`, commit, push:
```bash
cd ~/kubernetes/gitops-lab/platform
sed -i 's/g, student@lab.local, role:admin/g, student@lab.local, role:readonly/' rbac-cm.yaml
git -C ~/kubernetes commit -am "rbac: student readonly" && git -C ~/kubernetes push
```
5. Probeer in de UI (als `student`) een app te syncen. Daarna terugdraaien:
```bash
git -C ~/kubernetes revert --no-edit HEAD && git -C ~/kubernetes push
```

**Verificatie**
- `./argocd.sh sso enable` eindigt met "token ontvangen voor student@lab.local" en laat de identiteit zien die de
  API ziet (`student@lab.local ['student@lab.local']`).
- Stap 5 geeft `permission denied: applications, sync, lab/web-lab`.
- De lokale `admin` blijft werken: dat is je vangnet.

**Valkuilen**
- Zonder `url` in `argocd-cm` werkt de SSO-redirect niet.
- `dex.config` zonder `connectors`-sleutel wordt geweigerd; de lokale connector komt van
  `enablePasswordDB: true`.
- `scopes: '[groups, email]'` is nodig als je op e-mailadres mapt in plaats van op een groep.

🔗 **Begrippen:** [SSO met Dex](CONCEPTS.md#sso-dex) · [RBAC in Argo CD](CONCEPTS.md#rbac-argo) ·
[AppProject](CONCEPTS.md#appproject)

---

## g-12

### G-12 — Notificaties bij een mislukte sync

**Doel:** Een melding laten afgaan zonder SMTP of Slack, en snappen uit welke drie delen dat bestaat.

**Stappen**
1. De ontvanger draait al (`echo-receiver` in `lab-observability`): een klein Python-proces dat elke POST logt.
2. De configuratie staat in git: `platform/notifications-cm.yaml` (service, template, triggers, subscriptions).
3. Laat een sync falen:
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/gitops-lab/clusters/lab/optional/waves-fail.yaml
ssh ubuntu@192.168.122.11 'argocd app sync waves-fail'
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=lab-observability logs deploy/echo --tail=5'
```
Je ziet een JSON-regel met `"app":"waves-fail"`, de projectnaam, sync-status en de revisie.

**Valkuilen**
- Een app met `automated` sync en een falende hook blijft herproberen; de fase is dan `Running` en de trigger
  `Error/Failed` vuurt niet. Zet `automated` uit voor zo'n lab-app (zoals `waves-fail`).
- De notifications-controller leest de ConfigMap live: geen herstart nodig. Een fout in de Go-template geeft
  `Trigger 'on-sync-failed' FAILED` in zijn log.

🔗 **Begrippen:** [Notificaties](CONCEPTS.md#notificaties) · [Hooks](CONCEPTS.md#hooks) ·
[Argo CD-architectuur](CONCEPTS.md#argo-architectuur)

---

## g-13

### G-13 — Rollback, history en git revert

**Doel:** Het verschil voelen tussen terugrollen in Argo CD en terugdraaien in git.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 'argocd app history web-lab'
ssh ubuntu@192.168.122.11 'argocd app rollback web-lab 0'     # ← faalt met automated sync aan
ssh ubuntu@192.168.122.11 'argocd app set web-lab --sync-policy none'
ssh ubuntu@192.168.122.11 'argocd app rollback web-lab 0'
ssh ubuntu@192.168.122.11 'argocd app history web-lab'        # nieuwe regel met de oude commit
# terug naar main:
ssh ubuntu@192.168.122.11 'argocd app set web-lab --sync-policy automated --auto-prune --self-heal'
ssh ubuntu@192.168.122.11 'argocd app sync web-lab'
```

**Verificatie**
- De eerste rollback faalt met `rollback cannot be initiated when auto-sync is enabled`: bewust ontworpen, anders
  vechten rollback en automatiek om dezelfde app.
- `argocd app history` toont per sync een ID met de commit; na de rollback staat de app op een oude commit.

**Valkuilen**
- In dit lab beheert de root-app de Application: `argocd app set` is dus drift en wordt teruggezet. Dat is geen
  bug maar het punt van app-of-apps.
- De nette weg is `git revert`; dan blijft de geschiedenis kloppen en is er geen oude revisie die blijft hangen.

🔗 **Begrippen:** [Rollback en history](CONCEPTS.md#rollback) · [Sync-policy](CONCEPTS.md#sync-policy) ·
[Drift](CONCEPTS.md#drift)

---

## g-14

### G-14 — ignoreDifferences, Prune=false en ServerSideApply

**Doel:** De drie knoppen voor "dit verschil is geen fout" en "deze resource mag blijven".

**Stappen**

1. **ignoreDifferences** — haal `replicas` uit de vergelijking. In dit lab beheert de root-app de Application,
   dus je past hem aan **in git** (live patchen wordt teruggezet — dat is de les van G-08):
```bash
cd ~/kubernetes/gitops-lab/clusters/lab/apps
python3 - <<'EOF'
import pathlib
p = pathlib.Path('web-lab.yaml'); s = p.read_text()
s = s.replace("  destination:\n", """  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
  destination:
""")
p.write_text(s)
EOF
git -C ~/kubernetes commit -am "web-lab: replicas niet vergelijken" && git -C ~/kubernetes push
ssh ubuntu@192.168.122.11 'argocd app sync root && argocd app sync web-lab'
ssh ubuntu@192.168.122.11 'kubectl --namespace=web-lab scale deployment web --replicas=1'
sleep 30
ssh ubuntu@192.168.122.11 'kubectl --namespace=web-lab get deploy web -o jsonpath="{.spec.replicas}"; echo'
```
2. **Prune=false** — een resource die je nooit automatisch wilt verwijderen:
```bash
cd ~/kubernetes/gitops-lab/workloads/web/base
cat > tijdelijk.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tijdelijk
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
data:
  doel: "blijft staan, ook als hij uit git verdwijnt"
EOF
sed -i 's/  - configmap.yaml/  - configmap.yaml\n  - tijdelijk.yaml/' kustomization.yaml
git -C ~/kubernetes commit -am "tijdelijk met Prune=false" && git -C ~/kubernetes push
ssh ubuntu@192.168.122.11 'argocd app sync web-lab'
# nu uit git halen:
rm tijdelijk.yaml && sed -i '/  - tijdelijk.yaml/d' kustomization.yaml
git -C ~/kubernetes commit -am "tijdelijk weg uit git" && git -C ~/kubernetes push
ssh ubuntu@192.168.122.11 'argocd app sync web-lab'
```
3. **ServerSideApply** — bekijk `clusters/lab/optional/health-crd.yaml`: daar staat het aan, omdat CRD's te groot
   zijn voor de client-side apply-annotatie.

**Verificatie**
- Stap 1: de replicas blijven `1` en de app blijft `Synced`. Zonder `ignoreDifferences` zet `selfHeal` hem terug
  (probeer dat eerst, in G-03).
- Stap 2: de sync meldt `ignored (requires pruning)` en de ConfigMap blijft bestaan. Opruimen:
  `kubectl --namespace=web-lab delete configmap tijdelijk`.

**Valkuilen**
- `ignoreDifferences` verbergt een echt meningsverschil (HPA versus git). Documenteer waarom de regel er is.
- `Replace=true` lost een vastgelopen apply op met een korte onderbreking; het is geen standaardinstelling.
- Live patchen van een Application die door de root-app wordt beheerd, wordt bij de volgende reconciliatie
  teruggezet. Wijzig in git.

🔗 **Begrippen:** [ignoreDifferences](CONCEPTS.md#ignoredifferences) · [Prune](CONCEPTS.md#prune) ·
[Drift](CONCEPTS.md#drift) · [App-of-apps](CONCEPTS.md#app-of-apps)

---

## g-15

### G-15 — Een tweede cluster registreren

**Doel:** Een Application naar een ander cluster laten wijzen dan `in-cluster`.

**Stappen**
```bash
./argocd.sh cluster add      # registreert dezelfde API-server onder een tweede URL (lab-external)
./argocd.sh cluster list
```
Daarna de app die naar dat cluster deployt:
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/gitops-lab/clusters/lab/optional/multi-lab.yaml
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'argocd cluster list'          # lab-external: Successful
ssh ubuntu@192.168.122.11 'argocd app get multi-lab'
ssh ubuntu@192.168.122.11 'kubectl --namespace=multi-lab get deploy,pods'
```
De app gebruikt `destination: { name: lab-external }` in plaats van een server-URL.

**Waarom "dezelfde" API-server?** Je hebt geen tweede cluster nodig om de mechanica te leren: het cluster-secret,
de service account `argocd-manager`, de destination in het project en de keuze `name` versus `server` zijn
identiek. Met een echt tweede cluster vervang je alleen de URL in `argocd cluster add`.

**Valkuilen**
- Zonder destination in `platform/project.yaml` weigert Argo CD de app. Dat staat er nu al; haal de regel weg om
  de fout te zien.
- Verwijderen: `./argocd.sh cluster rm` (laat de namespace staan).

🔗 **Begrippen:** [Meerdere clusters](CONCEPTS.md#multi-cluster) · [AppProject](CONCEPTS.md#appproject) ·
[kubeconfig en contexts](../scripts/kubeadm-lab/CONCEPTS.md#kubeconfig)

---

## g-16

### G-16 — Eigen health-check (Lua) voor een CRD

**Doel:** Zien dat een custom resource zonder health-check altijd `Healthy` is, en dat oplossen.

**Stappen**
1. Zonder health-check:
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/gitops-lab/clusters/lab/optional/health-crd.yaml
ssh ubuntu@192.168.122.11 'argocd app get health-crd'      # Synced + Healthy, terwijl er niets "klaar" is
```
2. Nu met een Lua-check:
```bash
./argocd.sh health-crd enable
ssh ubuntu@192.168.122.11 'argocd app get health-crd --refresh'   # Progressing
```
3. De status zetten die de check verwacht:
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=lab-health patch widget demo --subresource=status --type=merge -p "{\"status\":{\"ready\":true}}"'
ssh ubuntu@192.168.122.11 'argocd app get health-crd'      # Healthy
```

**Verificatie:** `Progressing → Healthy`, puur op basis van het Lua-script in `argocd-cm`.

**Valkuilen**
- De check kijkt naar `obj.status`, dus je CRD moet een `status`-subresource hebben (staat in `crd.yaml`).
- Na het wijzigen van `argocd-cm` moet de application-controller herstarten; het script doet dat.
- Een fout in Lua geeft `Unknown` — geen crash, dus je merkt het pas aan de app-status.

🔗 **Begrippen:** [Eigen health-checks in Lua](CONCEPTS.md#health-check-lua) · [Health-status](CONCEPTS.md#health-status) ·
[CRD en CR](../scripts/kubeadm-lab/CONCEPTS.md#crd-cr)

---

## g-17

### G-17 — Image updater: tags automatiseren (optioneel)

**Doel:** Begrijpen hoe een controller nieuwe image-tags kan bijwerken, en waarom write-back naar git een
beslissing is.

**Stappen**
```bash
./argocd.sh image-updater install
./argocd.sh image-updater test
```
De `test`-opdracht vraagt aan de registry welke tags er zijn en welke hij zou kiezen — zonder iets te wijzigen.

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=argocd get deploy argocd-image-updater-controller'
ssh ubuntu@192.168.122.11 'kubectl get crd | grep imageupdater'
```
De uitvoer van `test` eindigt met `latest image according to constraint is <image>:<tag>`.

**Wat je hiermee leert**

| Vraag | Antwoord |
|---|---|
| Waar komt de nieuwe tag vandaan? | een registry-query, gefilterd met `allow-tags` of een semver-constraint |
| Waar schrijft hij het resultaat? | in de Application (parameter-override) of terug in git |
| Wil je dat? | alleen met een review-stap (branch + PR) of helemaal niet |

**Valkuilen**
- Zonder constraint kiest hij ook tags als `mainline-alpine3.21-perl`. Dat is geen "nieuwste versie", dat is ruis.
- Write-back naar `main` omzeilt je review. Schrijf naar een branch en laat de PR-flow beslissen.
- Private registries vragen credentials in een Secret; anoniem werkt alleen voor publieke images.

🔗 **Begrippen:** [Image updater](CONCEPTS.md#image-updater) · [Repo-credentials](CONCEPTS.md#repo-credentials) ·
[Pull-request-flow](../scripts/kubeadm-lab/CONCEPTS.md#pull-request-flow)

---

## g-18

### G-18 — Disaster recovery: alles uit git opnieuw

**Doel:** Meten hoe lang het duurt om je hele GitOps-omgeving terug te bouwen. Dat getal is je RTO.

**Stappen**
```bash
date
./argocd.sh uninstall      # namespace argocd + CRD's weg
./argocd.sh install        # leeg Argo CD terug
./argocd.sh login
./argocd.sh bootstrap      # root-app: de rest volgt uit git
./argocd.sh status
date
```

**Verificatie**
- Alle apps uit `clusters/lab/apps` zijn terug en `Synced` + `Healthy`.
- De web-pagina's, de Helm-release, de golven en de ApplicationSet-omgevingen bestaan weer.
- Het admin-wachtwoord is **nieuw** (het oude secret is weg).

**Wat niet terugkomt** (en dus bewust een script-stap is): de NodePort, SSO, de image updater en de registratie van
`lab-external`. Dat is de les: alles wat je met de hand doet, moet je bij een herstel opnieuw doen. Zet zulke
stappen in een script of in git.

**Valkuilen**
- Zonder `CreateNamespace=true` of een Namespace-manifest mislukt de eerste sync na herstel.
- Als je root-app niet in git staat, is er niets om opnieuw te bootstrappen. Daarom staat
  `bootstrap/root-app.yaml` in deze repo.
- `uninstall` verwijdert de CRD's; bestaande `Application`-objecten verdwijnen daarmee ook.

🔗 **Begrippen:** [Disaster recovery](CONCEPTS.md#disaster-recovery) · [App-of-apps](CONCEPTS.md#app-of-apps) ·
[Argo CD beheert zichzelf](CONCEPTS.md#self-management)

---

## Na deze labs

- **Flux ter vergelijking:** dezelfde apps met een `GitRepository` + `Kustomization`. Zie
  [STUDIEPLAN L-27](../scripts/kubeadm-lab/STUDIEPLAN.md).
- **Secrets:** Sealed Secrets of External Secrets erbij halen en dezelfde web-app met een Secret uitrollen
  ([#secrets-in-git](CONCEPTS.md#secrets-in-git)).
- **Monitoring van Argo CD zelf:** de componenten exposeren Prometheus-metrics; hang ze in de
  kube-prometheus-stack uit blok 7 en alert op `argocd_app_info{sync_status="OutOfSync"}`.
- **Kargo of Argo Rollouts:** geautomatiseerde promotie en canary-deploys bovenop deze structuur.
