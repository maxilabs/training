# secrets-lab — secret management met External Secrets Operator en Azure Key Vault

**Wat dit is.** Een lab waarin je leert hoe je secrets beheert zoals het hoort: niet in git, niet in een
Kubernetes Secret dat je met de hand maakt, maar in een **vault** die de bron van waarheid is — en een operator
in het cluster (ESO) die de waarden ophaalt en als gewone Kubernetes Secrets aanbiedt.

**Waarom.** Een Kubernetes Secret is base64, geen encryptie ([waarom dat uitmaakt](CONCEPTS.md#k8s-secret)).
Zodra je die YAML in git zet, staat je wachtwoord in de geschiedenis van je repo — en daar krijg je het nooit
meer uit ([secret-hygiëne](CONCEPTS.md#secret-hygiene)). De oplossing is niet "beter opletten", maar de
secret buiten git houden en het cluster laten pullen.

## De documenten

| Document | Rol |
|---|---|
| [LABS](LABS.md) | de labs S-01 t/m S-20, met stappen, verificatie en begrippen |
| [CONCEPTS](CONCEPTS.md) | elk begrip als los object: wat, waarom, hoe, zie het zelf, valkuilen |
| [SCRIPTS](SCRIPTS.md) | wat `../scripts/kubeadm-lab/secrets.sh` doet, met het handmatige equivalent |
| [ALTERNATIVES](ALTERNATIVES.md) | de andere opties (Vault/OpenBao, Sealed Secrets, SOPS, CSI, Infisical, Keycloak) met een keuzematrix |

Deze map hoort bij de vault: [README](../scripts/kubeadm-lab/README.md) · [STUDIEPLAN blok 9](../scripts/kubeadm-lab/STUDIEPLAN.md) ·
[CONCEPTS blok 9](../scripts/kubeadm-lab/CONCEPTS.md) · [gitops-lab](../gitops-lab/README.md) (Argo CD, waar deze
manifests door uitgerold worden).

## Snelstart

Vanaf **aristotle**, in `~/kubernetes/scripts/kubeadm-lab`:

```bash
./secrets.sh install        # ESO 2.14.0 via Argo CD (Helm-bron) + namespace secrets-lab
./secrets.sh azure init     # Key Vault + lees- en schrijf-identiteit + rollen + cluster-secrets
./secrets.sh azure seed     # voorbeeldsecrets in de vault
./secrets.sh stores         # SecretStore / ClusterSecretStore toepassen
./secrets.sh status         # ESO, stores en ExternalSecrets in één overzicht
```

Daarna begin je bij [LABS → S-04](LABS.md#s-04). Opruimen: `./secrets.sh reset` (lab-objecten) of
`./secrets.sh destroy` (ook de vault en de service principals).

## Wat er in deze map staat

```
secrets-lab/
├── platform/
│   ├── external-secrets.yaml     Argo CD-Application: ESO uit de Helm-chart
│   └── namespace.yaml            namespace secrets-lab (+ label voor de ClusterSecretStore)
├── stores/
│   ├── secretstore-azurekv.yaml          lezen, namespace-scoped
│   ├── secretstore-azurekv-writer.yaml   schrijven (PushSecret)
│   └── clustersecretstore-azurekv.yaml   clusterbreed, met namespace-conditie
├── workloads/
│   ├── app/             demo-app die zijn config uit een Secret leest
│   ├── demos/           01 basis, 02 extract, 03 template, 04 refresh, 05 deletionPolicy
│   ├── push/            PushSecret (Kubernetes -> Key Vault)
│   ├── cluster-wide/    ClusterExternalSecret (één definitie, veel namespaces)
│   └── openbao/         OpenBao (dev) als Azure-vrije backend
└── clusters/lab/        Applications voor de lab-omgeving (Argo CD)
```

## De rolverdeling (belangrijk om te snappen)

| Wie | Wat |
|---|---|
| **git** | de *verwijzing*: welk secret, uit welke vault, in welk Kubernetes Secret, met welke vorm |
| **Azure Key Vault** | de *waarde*: het wachtwoord, de API-key, het certificaat |
| **ESO** | de motor: haalt de waarde op, maakt/bijwerkt het Kubernetes Secret, doet dat continu |
| **jouw app** | leest gewoon een Kubernetes Secret; hij weet niet dat Key Vault bestaat |

Die scheiding is het hele punt: je kunt de vault vervangen (Azure → OpenBao) zonder je app of je git-repo te
wijzigen. Alleen de `secretStoreRef` verandert.

## Drie dingen die je hier leert en die je in productie tegenkomt

1. **Er is altijd één geheim dat je niet uit een vault kunt halen**: het credential waarmee je bij de vault komt
   ([bootstrap-credential](CONCEPTS.md#bootstrap-credential)). Dat is het echte ontwerpprobleem, niet de secrets
   zelf.
2. **Rechten zijn de kern.** De maker van een Key Vault heeft standaard géén toegang tot de secrets erin, en een
   lezer mag niet schrijven. Twee identiteiten, twee rollen, twee stores.
3. **Policy bepaalt je lab.** De landing zone heeft `purge protection` verplicht gesteld, dus een vaultnaam is
   na verwijderen 90 dagen bezet. Daarom maakt het script een unieke naam per installatie.

## Status van de Azure-kant

De labs zijn gebouwd op de landing zone uit de vending machine
(`landing-zone-vending-machine/payloads/k8s-secrets-dev-20261026.json`). Twee Azure-feiten dwingen een omweg:

| Feit | Gevolg |
|---|---|
| Het tenant-limiet van 5 subscriptions is bereikt, dus `create_new: true` faalt met `SubscriptionCountReachedLimit` | De lab-resources staan nu in de dev-subscription (`ml-cert-vm-dev-weu-sub`) in resource group `ml-rg-k8s-secrets-dev` — dezelfde namen als de payload, dus zodra er een slot vrij is kun je de payload alsnog laten lopen |
| De opgeruimde subscription staat **3 dagen** op `Warned`: Azure heeft een wachttijd voor handmatige verwijdering | Na die 3 dagen: subscription handmatig verwijderen in de portal (Subscriptions → de subscription → Delete), dan is het slot vrij en werkt `create_new: true` |
| De landing zone **enforced** purge protection (Azure Policy `Enforce-GR-KeyVault`, effect Deny) | Vaultnamen zijn 90 dagen gereserveerd na verwijderen; `secrets.sh` genereert daarom een suffix (`ml-kv-k8ssec-xxxx`) |

Zie [LABS S-02](LABS.md#s-02) voor het exacte Azure-commando en de volledige foutmelding.
