# LABS — secret management met ESO en Azure Key Vault

Elk lab: **doel → stappen → verificatie → begrippen**. Begrippen staan in [CONCEPTS](CONCEPTS.md), de commando's
komen uit `../scripts/kubeadm-lab/secrets.sh`.

**Uitgangspunt:** je werkt vanaf **aristotle** in `~/kubernetes/scripts/kubeadm-lab`. De scripts voeren
kubectl-werk uit op **cp1**. Azure-werk (Key Vault, rollen) doet `az` vanaf aristotle, met de subscription uit
`lab.env`.

| Lab | Onderwerp | Nodig |
|---|---|---|
| [S-01](#s-01) | Waarom: base64 is geen encryptie | — |
| [S-02](#s-02) | De landing zone uit de vending machine | Azure |
| [S-03](#s-03) | ESO installeren via Argo CD | Argo CD |
| [S-04](#s-04) | Je eerste ExternalSecret | Azure |
| [S-05](#s-05) | Wat als het Secret ontbreekt (ordening) | Azure |
| [S-06](#s-06) | `dataFrom`: extract en find | Azure |
| [S-07](#s-07) | Templating: van losse waarden naar bruikbare config | Azure |
| [S-08](#s-08) | Rotatie en refreshInterval | Azure |
| [S-09](#s-09) | deletionPolicy: wat mag er weg | Azure |
| [S-10](#s-10) | Drift: wie is de baas over het Secret | Azure |
| [S-11](#s-11) | ClusterExternalSecret: één definitie, veel namespaces | Azure |
| [S-12](#s-12) | PushSecret: van cluster naar vault | Azure |
| [S-13](#s-13) | Foutmodes en debuggen | Azure |
| [S-14](#s-14) | Least privilege: twee identiteiten | Azure |
| [S-15](#s-15) | Waarom workload identity hier niet werkt | Azure |
| [S-16](#s-16) | CSI-driver versus ESO | — |
| [S-17](#s-17) | OpenBao: dezelfde app, andere vault | — |
| [S-18](#s-18) | GitOps: de ExternalSecret in Argo CD | Argo CD |
| [S-19](#s-19) | Monitoring: weet je het als het misgaat | — |
| [S-20](#s-20) | Disaster recovery en de hele keten | alles |

---

## s-01

### S-01 — Waarom: base64 is geen encryptie

**Doel:** Zien dat een Kubernetes Secret leesbaar is voor iedereen met leesrechten, en dat "in git zetten" de
echte fout is.

**Stappen**
```bash
cd ~/kubernetes/scripts/kubeadm-lab
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab create secret generic demo --from-literal=wachtwoord=hunter2 --dry-run=client -o yaml' | tee /tmp/secret.yaml
grep wachtwoord /tmp/secret.yaml          # base64...
grep wachtwoord /tmp/secret.yaml | awk '{print $2}' | base64 -d; echo   # ...en zo lees je het terug
```

**Verificatie**
- Je ziet `aHVudGVyMg==` en daarachter `hunter2`. Base64 is een transportcodering, geen slot.
- Wie het Secret mag lezen (`get secret`), heeft de waarde. RBAC is hier je enige grens: dat is
  [namespace-isolatie](CONCEPTS.md#namespace-isolatie) plus [RBAC](../scripts/kubeadm-lab/CONCEPTS.md#rbac).

**Wat je hieruit meeneemt:** de vraag is niet "hoe versleutel ik mijn Secret", maar "waarom staat deze waarde
in mijn repo of in mijn YAML-bestand". Zet hem in een vault en laat het cluster hem halen
([External Secrets Operator](CONCEPTS.md#eso)).

🔗 **Begrippen:** [Kubernetes Secret](CONCEPTS.md#k8s-secret) · [Secret-hygiëne](CONCEPTS.md#secret-hygiene) ·
[etcd-encryptie](CONCEPTS.md#etcd-encryptie) · [Encryption at rest](../scripts/kubeadm-lab/CONCEPTS.md#encryption-at-rest)

---

## s-02

### S-02 — De landing zone uit de vending machine

**Doel:** De Azure-omgeving voor dit lab aanvragen zoals je dat in dit platform doet: met een **payload-JSON**
in `maxilabs/solutions`, niet met losse `az`-commando's.

**Stappen**
1. Bekijk de payload: `landing-zone-vending-machine/payloads/k8s-secrets-dev-20261026.json` in de
   solutions-repo. Gegenereerd met hun eigen generator:
   ```bash
   cd ~/Nextcloud/Development/MaxiLabs/Repositories/solutions/landing-zone-vending-machine
   pwsh ./scripts/New-LandingZonePayload.ps1 -WorkloadName k8s-secrets -DivisionName platform \
     -Environment dev -CostCenter CC001 -TechnicalContact maximusst@gmail.com \
     -BusinessOwner maximusst@gmail.com -ManagementGroupId maxilabs-corp \
     -RequireVNet -RequireStorageAccount
   ```
2. De payload committen op `main` start de pipeline (plan → apply). Handmatig kan ook:
   ```bash
   gh workflow run deploy-landing-zone.yml -R maxilabs/solutions \
     -f payload_file=k8s-secrets-dev-20261026.json -f action=plan
   ```

**Verificatie**
```bash
./secrets.sh lz      # subscription, resource group, vnet, vault
```
Je ziet resource group `ml-rg-k8s-secrets-dev` met de VNet uit de payload.

**Twee dingen die je hier leert (en die je niet in een boek vindt)**

| Situatie | Wat Azure zegt | Wat je doet |
|---|---|---|
| `create_new: true` terwijl het tenant-limiet (5 subscriptions) bereikt is | `SubscriptionCountReachedLimit` | Een bestaand dev-abonnement gebruiken en de payload op `create_new: false` + `subscription_id` zetten |
| De landing zone **enforced** purge protection (policy `Enforce-GR-KeyVault`, Deny) | De Key Vault-create faalt zonder `--enable-purge-protection` | Purge protection aanzetten en een unieke vaultnaam gebruiken (de naam blijft 90 dagen bezet) |
| Een geannuleerde subscription is pas na **3 dagen** handmatig te verwijderen | Het limiet blijft intussen gelden | Na 3 dagen: portal → Subscriptions → subscription → Delete; daarna `create_new: true` opnieuw draaien |

De Key Vault zit **niet** in de vending-machine-module (de payload heeft het veld, de Terraform niet). Daarom
maakt `secrets.sh azure init` de vault zelf, met dezelfde naam als in de payload zou staan.

🔗 **Begrippen:** [Landing zone als payload](CONCEPTS.md#lz-payload) · [Purge protection](CONCEPTS.md#kv-purge-protectie) ·
[Het lagenmodel](../scripts/kubeadm-lab/CONCEPTS.md#iac-lagen)

---

## s-03

### S-03 — ESO installeren via Argo CD

**Doel:** ESO als GitOps-component, niet met een losse `helm install`.

**Stappen**
```bash
./secrets.sh install
```
Wat er gebeurt: Argo CD rendert de chart `external-secrets` 2.14.0 uit `https://charts.external-secrets.io` en
past hem toe. Er is **geen** helm-binary op de node nodig.

**Verificatie**
```bash
./secrets.sh status
ssh ubuntu@192.168.122.11 'kubectl get crd | grep external-secrets | wc -l'   # 25
```

**De twee fouten die je hier tegenkomt** (allebei echt gebeurd bij het bouwen van dit lab):
1. `application repo https://charts.external-secrets.io is not permitted in project 'lab'` → de chart-repo moet in
   `sourceRepos` van het AppProject staan.
2. `resource rbac.authorization.k8s.io:ClusterRole is not permitted in project 'lab'` → een operator heeft
   clusterbrede rechten; die moeten in `clusterResourceWhitelist` ([AppProject](../gitops-lab/CONCEPTS.md#appproject)).

Beide staan nu in `gitops-lab/platform/project.yaml`. Dat is de les: **een platform-component toevoegen is ook
een AppProject-wijziging**, en die hoort in git.

🔗 **Begrippen:** [ESO-architectuur](CONCEPTS.md#eso-architectuur) · [AppProject](../gitops-lab/CONCEPTS.md#appproject) ·
[Helm als bron](../gitops-lab/CONCEPTS.md#helm-in-argo)

---

## s-04

### S-04 — Je eerste ExternalSecret

**Doel:** Eén sleutel uit Azure Key Vault als Kubernetes Secret.

**Stappen**
```bash
./secrets.sh azure init      # vault + lees- en schrijf-identiteit + rollen + cluster-secrets
./secrets.sh azure seed       # db-password, app-config, rotating-secret in de vault
./secrets.sh stores           # SecretStore + ClusterSecretStore
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/secrets-lab/workloads/demos/01-basic.yaml
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab get externalsecret db-password'
# STATUS: SecretSynced   READY: True
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab get secret db-password -o jsonpath='{.data.password}' | base64 -d | wc -c"
```
Het aantal tekens komt overeen met het wachtwoord in de vault; de waarde zelf print je niet.

**Wat ESO hier doet:** de ExternalSecret noemt een `secretKey` (naam in Kubernetes) en een `remoteRef.key`
(naam in Key Vault). ESO haalt de waarde op en schrijft het Secret. Bij elke `refreshInterval` opnieuw.

🔗 **Begrippen:** [ExternalSecret](CONCEPTS.md#externalsecret) · [SecretStore](CONCEPTS.md#secretstore) ·
[Rotatie](CONCEPTS.md#rotatie)

---

## s-05

### S-05 — Wat als het Secret ontbreekt (ordening)

**Doel:** De klassieke `CreateContainerConfigError` begrijpen: je app start niet omdat zijn Secret er nog niet is.

**Stappen**
```bash
# De demo-app hangt aan het Secret 'app-config-templated'
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab delete secret app-config-templated'
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab rollout restart deploy/secrets-demo'
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab get pods -l app=secrets-demo'
# STATUS: CreateContainerConfigError
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab describe pod -l app=secrets-demo | tail -5'
# Error: secret "app-config-templated" not found
```
Los het op door de ExternalSecret te laten syncen (die maakt het Secret opnieuw):
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab annotate externalsecret app-config-templated force-sync="'$(date +%s)'" --overwrite'
```

**De les:** in een GitOps-cluster is volgorde een ontwerpprobleem. Een Secret dat door ESO komt, bestaat pas
nadat ESO hem gesynct heeft. Los dat op met `sync-wave` ([sync waves](../gitops-lab/CONCEPTS.md#sync-waves)) of
met een app die pas start als de Secret er is — niet met "gewoon nog een keer applyen".

🔗 **Begrippen:** [ExternalSecret](CONCEPTS.md#externalsecret) · [Sync waves](../gitops-lab/CONCEPTS.md#sync-waves) ·
[Pod-levenscyclus](../scripts/kubeadm-lab/CONCEPTS.md#pod-lifecycle)

---

## s-06

### S-06 — `dataFrom`: extract en find

**Doel:** Niet elke sleutel los opnoemen, maar een heel object uit de vault overnemen.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/secrets-lab/workloads/demos/02-datafrom-extract.yaml
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab get secret app-config -o jsonpath='{.data}' | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))'"
```

**Verificatie:** je ziet `['api_key', 'password', 'smtp_password', 'username']` — vier sleutels uit één
Key Vault-secret dat JSON bevat.

| Vorm | Wat het doet | Valkuil |
|---|---|---|
| `data[].remoteRef` | één sleutel per stuk | veel regels, foutgevoelig |
| `dataFrom.extract` | alle sleutels onder één vault-secret | de *namen* komen uit de JSON; hoofdletters/kleine letters blijven zoals ze zijn |
| `dataFrom.find` | zoekt op naam/tag in de vault | vraagt `list`-rechten op de vault |

**De valkuil die je ziet in S-07:** `api_key` wordt als env var `api_key`, niet `API_KEY`. Je app zoekt
`API_KEY` en vindt niets. Daarom renderen we in de praktijk met een template.

🔗 **Begrippen:** [`dataFrom` versus `data`](CONCEPTS.md#datafrom) · [Key Vault-objecten](CONCEPTS.md#kv-objecten)

---

## s-07

### S-07 — Templating: van losse waarden naar bruikbare config

**Doel:** Waarden combineren tot wat je app nodig heeft, met de template-engine van ESO.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/secrets-lab/workloads/demos/03-template.yaml
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab rollout restart deploy/secrets-demo'
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab exec deploy/secrets-demo -- wget -qO- http://127.0.0.1:8080/"
# DATABASE_URL: aanwezig (93 tekens) · API_KEY: aanwezig (32) · SMTP_PASSWORD: aanwezig (24)
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab get secret app-config-templated -o jsonpath='{.data.DATABASE_URL}' | base64 -d"
# postgres://appuser:...@postgres.secrets-lab.svc:5432/app?sslmode=require
```

**Wat je hier leert**
- `engineVersion: v2` geeft je Sprig-functies: `sha256sum`, `trunc`, `default`, `b64enc`, `upper`.
- Een checksum in het Secret (`CONFIG_CHECKSUM`) is een handige manier om een rollout af te dwingen.
- **Eén Secret, één eigenaar.** Twee ExternalSecrets met dezelfde `target.name` geven
  `SecretOwnedByOther`. Dat is precies de fout die je in een echt cluster vindt; hier hebben we hem bewust
  veroorzaakt en opgelost door de template-demo een eigen Secret te geven.

🔗 **Begrippen:** [Templating](CONCEPTS.md#templating) · [ExternalSecret](CONCEPTS.md#externalsecret)

---

## s-08

### S-08 — Rotatie en refreshInterval

**Doel:** Zien dat een nieuwe waarde in de vault vanzelf in het cluster komt — en dat je Pod niet meebeweegt.

**Stappen**
1. Zet een nieuwe waarde in de vault:
```bash
KV=$(cat ~/.config/secrets-lab/vault-name)
az keyvault secret set --vault-name "$KV" --name rotating-secret --value "ronde-$(date +%s)" \
  --subscription ee758b7e-a761-4c31-aebc-fa2ac39abe32 --query name -o tsv
```
2. Kijk hoe lang het duurt:
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab get externalsecret rotating'
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab get secret rotating -o jsonpath='{.data.value}' | base64 -d"
```

**Verificatie:** binnen ±30 seconden (de `refreshInterval` van deze ExternalSecret) staat de nieuwe waarde in
het Secret. De **Pod** verandert niet: een Secret dat als env var binnenkomt, geldt voor de levensduur van de
container.

| Mount | Werkt de waarde bij in de Pod? |
|---|---|
| `env` / `envFrom` | nee, pas na herstart |
| volume | ja, binnen ±1 minuut (kubelet-sync) |

Dat verschil is de reden dat veel teams een checksum-annotatie gebruiken om een rollout te forceren
([S-07](#s-07)).

🔗 **Begrippen:** [Rotatie](CONCEPTS.md#rotatie) · [Refresh en drift](CONCEPTS.md#drift-secret)

---

## s-09

### S-09 — deletionPolicy: wat mag er weg

**Doel:** Bewust kiezen wat er met het Kubernetes Secret gebeurt als de ExternalSecret verdwijnt.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/secrets-lab/workloads/demos/05-deletion-policy.yaml
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab delete externalsecret retain-demo delete-demo'
sleep 5
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab get secret retain-demo delete-demo'
```

**Verificatie:** `retain-demo` bestaat nog, `delete-demo` is weg.

| Policy | Effect | Wanneer |
|---|---|---|
| `Retain` | Secret blijft staan | standaard, veilig |
| `Merge` | Secret blijft, sleutels worden niet opgeruimd | meerdere bronnen in één Secret |
| `Delete` | Secret verdwijnt | alleen als de app zonder kan |

**De productiefout die je hiermee voorkomt:** een map uit git verwijderen, Argo CD laten prunen, en dan
ontdekken dat je de configuratie van je productie-app hebt weggegooid.

🔗 **Begrippen:** [deletionPolicy](CONCEPTS.md#deletion-policy) · [Prune](../gitops-lab/CONCEPTS.md#prune)

---

## s-10

### S-10 — Drift: wie is de baas over het Secret

**Doel:** Voelen dat ESO het Secret terugzet, net zoals Argo CD dat met andere resources doet.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab patch secret db-password --type=merge -p "{\"data\":{\"password\":\"Z2VrbmFrdA==\"}}"'
sleep 65
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab get secret db-password -o jsonpath='{.data.password}' | base64 -d"
```

**Verificatie:** je handmatige waarde (`geknakt`) is binnen één refresh weer de echte waarde uit de vault.

**Twee eigenaren, één Secret:** ESO beheert de inhoud, jij beheert de ExternalSecret (via git). Wie iets wil
wijzigen doet dat in de vault of in de ExternalSecret — niet met `kubectl patch`.

🔗 **Begrippen:** [Refresh en drift](CONCEPTS.md#drift-secret) · [Drift](../gitops-lab/CONCEPTS.md#drift)

---

## s-11

### S-11 — ClusterExternalSecret: één definitie, veel namespaces

**Doel:** Een gedeelde configuratie uitrollen naar elke team-namespace, zonder N losse ExternalSecrets.

**Stappen**
```bash
for ns in secrets-team-a secrets-team-b; do
  ssh ubuntu@192.168.122.11 "kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -"
  ssh ubuntu@192.168.122.11 "kubectl label namespace $ns secrets.maxilabs.dev/team=true secrets.maxilabs.dev/azure-kv=true --overwrite"
done
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/secrets-lab/workloads/cluster-wide/clusterexternalsecret.yaml
```

**Verificatie**
```bash
ssh ubuntu@192.168.122.11 'kubectl get clusterexternalsecret team-shared-config'
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-team-a get externalsecret,secret team-shared-config'
```
Beide namespaces hebben een eigen ExternalSecret **en** een eigen Secret, allebei door dezelfde CR beheerd.

**Twee grendels die je hier ziet**
1. De ClusterExternalSecret selecteert namespaces op label `secrets.maxilabs.dev/team=true`.
2. De ClusterSecretStore is alleen actief in namespaces met `secrets.maxilabs.dev/azure-kv=true` — een tweede
   grens, zodat een team niet per ongeluk andermans vault leest.

🔗 **Begrippen:** [ClusterExternalSecret](CONCEPTS.md#clusterexternalsecret) ·
[Namespace-isolatie](CONCEPTS.md#namespace-isolatie) · [Multi-tenant](CONCEPTS.md#multi-tenant)

---

## s-12

### S-12 — PushSecret: van cluster naar vault

**Doel:** De omgekeerde richting: een waarde die in het cluster is ontstaan, veilig opslaan in de vault.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab create secret generic push-source --from-literal=token=bootstrap-$(date +%s) --dry-run=client -o yaml | kubectl apply -f -"
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' < ~/kubernetes/secrets-lab/workloads/push/pushsecret.yaml
sleep 20
KV=$(cat ~/.config/secrets-lab/vault-name)
az keyvault secret show --vault-name "$KV" --name pushed-token --subscription ee758b7e-a761-4c31-aebc-fa2ac39abe32 --query '{naam:name,versie:attributes.updated}' -o table
```

**Verificatie:** `pushed-token` staat in Key Vault, met een verse versie.

**Waarom dit een eigen identiteit gebruikt:** schrijven vraagt `Key Vault Secrets Officer`, lezen vraagt
`Key Vault Secrets User`. De PushSecret verwijst daarom naar `azure-kv-writer`; de lees-identiteit kan niets
wijzigen ([least privilege](#s-14)).

**Valkuil:** `deletionPolicy: Delete` op een PushSecret betekent dat het **bron-secret in de vault** verdwijnt
als je de PushSecret opruimt. In dit lab staat hij op `None` — bewust.

🔗 **Begrippen:** [PushSecret](CONCEPTS.md#pushsecret) · [Service principal](CONCEPTS.md#service-principal)

---

## s-13

### S-13 — Foutmodes en debuggen

**Doel:** De vier fouten die je in productie 90% van de tijd tegenkomt herkennen aan hun melding.

**Stappen**
```bash
# 1. verkeerd client-secret
ssh ubuntu@192.168.122.11 "kubectl --namespace=secrets-lab patch secret azure-sp-reader --type=merge -p '{\"data\":{\"ClientSecret\":\"ZmFscy11aXQ=\"}}'"
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab annotate externalsecret db-password force-sync=x --overwrite'
./secrets.sh debug db-password
# 2. herstel
./secrets.sh azure init       # zet het juiste secret terug
```

**Verificatie en de bijbehorende meldingen**

| Fout | Melding | Oorzaak |
|---|---|---|
| verkeerd secret | `failed to get credential ... AADSTS7000215` | client-secret niet (meer) geldig |
| geen rechten | `ForbiddenByRbac` / `403` | rol ontbreekt op de vault |
| verkeerde vault-URL | `dial tcp: no such host` | tikfout of vault bestaat niet |
| secret bestaat niet | `SecretNotFound` | naam in `remoteRef.key` klopt niet |
| twee apps, één Secret | `SecretOwnedByOther` | tweede ExternalSecret op dezelfde `target.name` |

**Je gereedschap:** `kubectl describe externalsecret`, de conditie `Ready` met `reason` en `message`, de events,
en de ESO-log. `./secrets.sh debug <naam>` doet alle drie.

🔗 **Begrippen:** [Foutmodes](CONCEPTS.md#foutmodes) · [Logs en events](../scripts/kubeadm-lab/CONCEPTS.md#logs-events)

---

## s-14

### S-14 — Least privilege: twee identiteiten

**Doel:** Aantonen dat de lezer niet kan schrijven en de schrijver niet meer dan nodig.

**Stappen**
```bash
KV=$(cat ~/.config/secrets-lab/vault-name)
read -r APP_ID _ <<< "$(jq -r '.appId' ~/.config/secrets-lab/sp-eso-k8s-reader.json)"
read -r APP_ID2 _ <<< "$(jq -r '.appId' ~/.config/secrets-lab/sp-eso-k8s-writer.json)"
echo "reader: $APP_ID"; echo "writer: $APP_ID2"
az role assignment list --assignee "$APP_ID" --scope "$(az keyvault show -n "$KV" --query id -o tsv --subscription ee758b7e-a761-4c31-aebc-fa2ac39abe32)" --query '[].roleDefinitionName' -o tsv
az role assignment list --assignee "$APP_ID2" --scope "$(az keyvault show -n "$KV" --query id -o tsv --subscription ee758b7e-a761-4c31-aebc-fa2ac39abe32)" --query '[].roleDefinitionName' -o tsv
```

**Verificatie:** `Key Vault Secrets User` voor de lezer, `Key Vault Secrets Officer` voor de schrijver.

**Wat je hier leert over Key Vault-rechten**
- `Key Vault Secrets User` = lezen (én de lijst zien, nodig voor `dataFrom.find`).
- `Key Vault Secrets Officer` = lezen + schrijven + verwijderen van secrets (maar niet van de vault zelf).
- De **maker** van een vault krijgt deze rechten niet automatisch: daarom vraagt `secrets.sh` expliciet
  `Officer` voor jouw gebruiker, puur om te kunnen seeden.

🔗 **Begrippen:** [Key Vault RBAC versus access policies](CONCEPTS.md#kv-rbac-vs-policy) ·
[Service principal](CONCEPTS.md#service-principal) · [RBAC](../scripts/kubeadm-lab/CONCEPTS.md#rbac)

---

## s-15

### S-15 — Waarom workload identity hier niet werkt

**Doel:** Begrijpen waarom je op AKS geen client-secret nodig hebt en op dit kubeadm-cluster wel.

**Stappen** (lezen en controleren, niet iets kapotmaken)
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=kube-system get cm kube-root-ca.crt >/dev/null && echo "cluster heeft een eigen CA"'
ssh ubuntu@192.168.122.11 'kubectl get --raw /.well-known/openid-configuration 2>/dev/null | head -5 || echo "geen publieke OIDC-discovery"'
```

**Verificatie:** de OIDC-discovery van je cluster is niet publiek bereikbaar (het cluster hangt in
192.168.122.0/24). Azure workload identity federation eist een **publiek** bereikbare issuer-URL: Entra ID moet
de token van je ServiceAccount kunnen valideren. Zonder dat blijft alleen een service principal over.

| Omgeving | Auth voor ESO | Waarom |
|---|---|---|
| AKS met workload identity | `authType: WorkloadIdentity` + federated credential | publieke issuer, geen secret nodig |
| dit lab (kubeadm, privé) | `authType: ServicePrincipal` met client-secret of certificaat | issuer niet bereikbaar |
| cluster met publieke OIDC | workload identity mogelijk | issuer moet HTTPS en publiek zijn |

**Wat je hiervan meeneemt:** het bootstrap-credential is geen slechte gewoonte maar een gevolg van je
netwerkarchitectuur. Zodra je een publieke issuer hebt, kun je het weghalen
([workload identity](CONCEPTS.md#workload-identity)).

🔗 **Begrippen:** [Workload identity](CONCEPTS.md#workload-identity) · [Bootstrap-credential](CONCEPTS.md#bootstrap-credential) ·
[ServiceAccount](../scripts/kubeadm-lab/CONCEPTS.md#serviceaccount)

---

## s-16

### S-16 — CSI-driver versus ESO

**Doel:** Het alternatief kennen en weten wanneer je het kiest.

**Hoe het werkt, zonder iets te installeren**

| | Secrets Store CSI Driver | ESO (dit lab) |
|---|---|---|
| Resultaat | mount als **volume** in de Pod | gewoon **Kubernetes Secret** |
| Zichtbaar in `kubectl get secrets` | nee | ja |
| `envFrom` mogelijk | nee (volume-only) | ja |
| Rotatie in de Pod | ja, bij volume-mount | nee bij env, ja bij volume |
| Delen tussen workloads | via `secretProviderClass` | via Secret of ClusterExternalSecret |
| Extra component | CSI-driver + provider + DaemonSet per node | één operator |

**Wanneer welk:** wil je dat de waarde **nooit** als Kubernetes Secret bestaat ( strengere eis), dan is de
CSI-driver logischer. Wil je dat je app gewoon `envFrom` kan gebruiken en dat je secrets in de rest van je
platform hetzelfde werken, dan is ESO praktischer. Veel organisaties draaien beide, voor verschillende
workloads.

🔗 **Begrippen:** [CSI-driver](CONCEPTS.md#csi-driver) · [ESO](CONCEPTS.md#eso) · [Vergelijking](ALTERNATIVES.md)

---

## s-17

### S-17 — OpenBao: dezelfde app, andere vault

**Doel:** Bewwijzen dat ESO je loskoppelt van de leverancier.

**Stappen**
```bash
./secrets.sh openbao
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab get secretstore,externalsecret openbao openbao-demo'
```

**Verificatie:** `openbao-demo` is `SecretSynced` uit een **tweede** vault, naast de Azure-vault. Vergelijk
`workloads/openbao/externalsecret.yaml` met `workloads/demos/02-datafrom-extract.yaml`: alleen
`secretStoreRef` en het pad verschillen.

**Waarschuwing:** dit is dev-modus (alles in geheugen, root-token). Voor productie heb je persistentie,
`unseal`, policies en Kubernetes-auth nodig. Zie [ALTERNATIVES](ALTERNATIVES.md#vault-en-openbao).

🔗 **Begrippen:** [Vault en OpenBao](CONCEPTS.md#vault-openbao) · [ESO](CONCEPTS.md#eso)

---

## s-18

### S-18 — GitOps: de ExternalSecret in Argo CD

**Doel:** De ExternalSecret zelf ook via Argo CD uitrollen, zodat de verwijzing naar de vault in git staat en de
waarde niet.

**Stappen**
1. Zet een Application neer (net als in [gitops-lab](../gitops-lab/LABS.md#g-08)):
```bash
ssh ubuntu@192.168.122.11 'kubectl apply --filename=-' <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: secrets-lab-demos, namespace: argocd}
spec:
  project: lab
  source:
    repoURL: https://github.com/maxilabs/training.git
    targetRevision: main
    path: kubernetes/secrets-lab/workloads/demos
  destination: {server: https://kubernetes.default.svc, namespace: secrets-lab}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
EOF
```
2. Bekijk wat er in git staat en wat er in het cluster staat:
```bash
grep -c . ~/kubernetes/secrets-lab/workloads/demos/*.yaml     # alleen verwijzingen
ssh ubuntu@192.168.122.11 'kubectl --namespace=secrets-lab get externalsecrets'
```

**Verificatie:** de ExternalSecrets worden `Synced` door Argo CD, en in git staat **geen enkele waarde**.

**De grens die je moet snappen:** Argo CD beheert de *ExternalSecret* (een CR), ESO beheert het resulterende
*Secret*. Twee controllers, twee verantwoordelijkheden. Zet het Secret niet in git "omdat Argo CD het dan kan
beheren" — dan ben je terug bij [S-01](#s-01).

🔗 **Begrippen:** [GitOps en secrets](CONCEPTS.md#gitops-secrets) · [Applicatie](../gitops-lab/CONCEPTS.md#applicatie) ·
[Self-management](../gitops-lab/CONCEPTS.md#self-management)

---

## s-19

### S-19 — Monitoring: weet je het als het misgaat

**Doel:** Een falende sync opmerken zonder in de UI te kijken.

**Stappen**
```bash
ssh ubuntu@192.168.122.11 'kubectl --namespace=external-secrets get svc external-secrets-metrics'
ssh ubuntu@192.168.122.11 "kubectl --namespace=external-secrets get --raw /api/v1/namespaces/external-secrets/services/http:external-secrets-metrics:8080/proxy/metrics 2>/dev/null | grep -E '^externalsecret_status_condition' | head -5"
```

**Verificatie:** je ziet metrics met een label per ExternalSecret en per conditie. Handige om op te alarmeren:

| Metric | Alert |
|---|---|
| `externalsecret_status_condition{condition="Ready",status="False"}` | een ExternalSecret is niet klaar |
| `externalsecret_sync_calls_error` | ESO kan de vault niet bereiken |
| `externalsecret_reconcile_duration_seconds` | trage vault |

Koppel dit aan de kube-prometheus-stack uit blok 7
([STUDIEPLAN L-26](../scripts/kubeadm-lab/STUDIEPLAN.md)) en je hebt dezelfde alert-stijl als voor je
Argo CD-apps.

🔗 **Begrippen:** [Observability](CONCEPTS.md#observability)
· [Prometheus-stack](../scripts/kubeadm-lab/CONCEPTS.md#prometheus-stack)

---

## s-20

### S-20 — Disaster recovery en de hele keten

**Doel:** De hele keten een keer stukmaken en herstellen: dat is het enige bewijs dat je hem snapt.

**Stappen**
```bash
# 1. ESO weg, cluster-secrets weg
./secrets.sh reset
ssh ubuntu@192.168.122.11 'kubectl --namespace=argocd delete application external-secrets'
# 2. opnieuw opbouwen
./secrets.sh install
./secrets.sh azure init
./secrets.sh stores
./secrets.sh status
```

**Verificatie:** binnen enkele minuten staan alle ExternalSecrets weer op `SecretSynced`, met dezelfde waarden
als in de vault. Je hoefde **geen enkele secret opnieuw te bedenken** — dat is het punt.

**Wat je hierbij leert over de grenzen van GitOps**

| Onderdeel | Bron van waarheid | Herstel |
|---|---|---|
| ExternalSecrets, stores, apps | git | Argo CD synct opnieuw |
| de waarden | Key Vault | blijven staan (soft-delete 90 dagen) |
| het bootstrap-credential | jouw `~/.config/secrets-lab/` + Entra | opnieuw zetten met `secrets.sh azure init` |
| de vault zelf | Azure (policy: purge protection) | niet te hergebruiken: naam 90 dagen bezet |

**De laatste les:** alles wat je met de hand doet, moet je bij een herstel opnieuw doen. Daarom zijn
`azure init` en `stores` scripts en geen losse commando's in een document.

🔗 **Begrippen:** [Disaster recovery](CONCEPTS.md#disaster-recovery) ·
[Disaster recovery (Argo CD)](../gitops-lab/CONCEPTS.md#disaster-recovery)

---

## Na deze labs

- **Sealed Secrets of SOPS** proberen voor het bootstrap-credential: dan staat ook dat ene secret in git
  ([ALTERNATIVES](ALTERNATIVES.md#sealed-secrets)).
- **CSI-driver** naast ESO zetten en het verschil in rotatie meten ([S-16](#s-16)).
- **Key Vault private endpoint**: de policy `Enforce-GR-KeyVault` vraagt in strengere varianten ook
  netwerkbeperking; dan moet je ESO via een private endpoint laten praten
  ([Key Vault-netwerk](CONCEPTS.md#kv-netwerk)).
- **Certificaten**: ESO kan ook Key Vault-**certificates** ophalen; oefen met een cert-only object en kijk wat
  er gebeurt als het verloopt.
