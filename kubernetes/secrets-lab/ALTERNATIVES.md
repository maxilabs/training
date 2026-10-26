# ALTERNATIVES — welke vault, en wanneer

Je vroeg naast Key Vault + ESO ook om een beeld van de andere opties. Dit is geen uitputtende marktanalyse maar
een **keuzedocument**: wat elk instrument echt doet, waar het je geld of tijd kost, en wanneer je het kiest.

> **Eerst een misverstand uit de weg: Keycloak is geen vault.** Keycloak is een identity provider (login, OIDC,
> SAML, MFA). Het heeft een `Vault SPI` — daarmee haalt Keycloak *zijn eigen* configuratie-secrets (SMTP,
> LDAP-bind, client-secrets) uit een externe kluis. Het is dus een **gebruiker** van een vault. Zie
> [Keycloak verderop](#keycloak) en [CONCEPTS](CONCEPTS.md#keycloak).

## De vier families

| Familie | Voorbeelden | Kern |
|---|---|---|
| **Centrale vault + operator** | Azure Key Vault + ESO, AWS Secrets Manager + ESO, Vault/OpenBao + ESO | één bron van waarheid, cluster haalt op |
| **Git-native, versleuteld** | Sealed Secrets, SOPS + age/KMS | het geheim staat in git, maar onleesbaar |
| **Volume-gebaseerd** | Secrets Store CSI Driver | de waarde bestaat nooit als Kubernetes Secret |
| **SaaS secret-managers** | Infisical, Doppler, 1Password Connect | beheer-UI + SDK/operator, vaak klein team |

## Keuzematrix

| | Azure Key Vault + ESO | Vault / OpenBao + ESO | Sealed Secrets | SOPS + age | CSI Driver | Infisical (self-host) |
|---|---|---|---|---|---|---|
| Waarde in git | verwijzing | verwijzing | **versleuteld** | **versleuteld** | verwijzing | verwijzing |
| Waarde in K8s Secret | ja | ja | ja | ja | **nee** (volume) | ja |
| `envFrom` | ja | ja | ja | ja | nee | ja |
| Rotatie zonder herstart | volume wél, env niet | idem | nee | nee | ja | idem |
| Dynamische secrets (DB-creds op tijd) | beperkt | **sterk** | nee | nee | via provider | beperkt |
| Audit per secret | ja (Azure-log) | ja | nee | nee | ja | ja |
| Beheer-last | laag (SaaS/PaaS) | **hoog** (HA, unseal, back-up) | laag | laag–midden | midden (DaemonSet) | midden |
| Kosten | per 10k operaties | infra + persoon | €0 | €0 | €0 | infra |
| Vendor lock-in | Azure | laag | geen | geen (age) | per provider | laag |
| Geschikt voor | **Azure-omgevingen** | multi-cloud, dynamische secrets | kleine teams, simpele GitOps | GitOps met leesbare diffs | strenge compliance | teams zonder cloud-vault |

## Azure Key Vault + ESO (dit lab)

**Wat:** Key Vault is de bron; ESO haalt op en maakt Kubernetes Secrets. In de labs bewezen: sync, templating,
rotatie, `dataFrom`, `PushSecret`, `ClusterExternalSecret`.

**Kies dit als:** je al in Azure zit, je compliance/audit in Azure wilt (diagnostic settings, Defender for Cloud),
en je geen vault wilt beheren.

**Nadelen:**
- **Beheer-model**: RBAC + policies (zoals purge protection verplicht) bepalen wat je mag; dat is krachtig maar
  star.
- **Geen echte dynamische secrets**: je kunt geen database-credential laten uitgeven met een lease van een uur.
- **Kosten per operatie**: bij zeer frequente `refreshInterval` (elke 30 s × veel ExternalSecrets) telt dat.
- **Netwerk**: private endpoint + DNS is het lastigste deel van een productie-uitrol.

## Vault en OpenBao

**Wat:** HashiCorp Vault is de referentie-implementatie van een secret-manager. Na de licentie-wijziging naar
BSL is **OpenBao** de open-source fork (MPL-2.0, Linux Foundation) met dezelfde API — je kunt dus dezelfde
ESO-provider (`vault`) gebruiken. In dit lab bewezen met OpenBao 2.7.1 in dev-modus.

**Kies dit als:** je dynamische secrets wilt (database-credentials met een lease), multi-cloud wilt, of secrets
wilt uitgeven op basis van Kubernetes-identiteit in plaats van een gedeeld client-secret.

**Nadelen:**
- Je beheert een stateful systeem met unseal-keys, HA en back-up. Dat is een dag per maand, niet een dag per jaar.
- Zonder goede policies is Vault een heel krachtig wachtwoordbestand.
- Dev-modus (zoals in [LAB S-17](LABS.md#s-17)) is géén productie.

**Migreren tussen beide is triviaal in ESO:** alleen `secretStoreRef` en het pad veranderen, de rest van je
manifests blijft. Dat is precies de reden om ESO als abstractie te gebruiken.

## Sealed Secrets

**Wat:** `kubeseal` versleutelt een Secret met de publieke sleutel van een controller in het cluster; de
versleutelde `SealedSecret` mag in git.

**Kies dit als:** je een kleine omgeving hebt, je repo self-contained wilt houden, en je geen externe vault
wilt beheren.

**Nadelen:**
- De privésleutel in het cluster is je bootstrap-credential: verlies je die, dan is je hele repo onbruikbaar.
- Geen centrale rotatie of audit; het geheim staat nog steeds in git (versleuteld).
- Namespace- en naamgebonden: verplaatsen betekent opnieuw sealen.

```bash
# illustratief; niet in dit lab geïnstalleerd
kubeseal --format yaml < secret.yaml > sealedsecret.yaml
```

## SOPS en age

**Wat:** SOPS versleutelt de *waarden* in een YAML-bestand; de structuur blijft leesbaar, dus je diffs zijn
begrijpelijk. Met **age** is de sleutel lokaal, met Azure Key Vault KMS is er geen privésleutel in je repo.

**Kies dit als:** je GitOps doet (Argo CD of Flux) en je wilt dat ook de secrets in git staan, met leesbare
reviews.

**Nadelen:**
- Met age heb je een privésleutel in het cluster (of in je pipeline) — opnieuw een bootstrap-credential.
- De ESO-SOPS-provider of Flux-detailopstelling is extra configuratie.
- Voor sleutelrotatie moet je opnieuw versleutelen.

```bash
# illustratief
sops --encrypt --age <public-key> secret.yaml > secret.enc.yaml
```

## Secrets Store CSI Driver

**Wat:** Een DaemonSet + provider die een vault-secret als **volume** in de Pod mount, zonder een Kubernetes
Secret-object. Azure heeft een eigen provider (`secrets-store-csi-driver-provider-azure`).

**Kies dit als:** je eist dat de waarde nooit in etcd staat, of als je secret als bestand nodig hebt
(certificaten, TLS-keystores).

**Nadelen:**
- Geen `envFrom`: je app moet het bestand lezen.
- Meer componenten (driver per node) en dus meer upgrade-werk.
- Delen tussen workloads gaat via `SecretProviderClass`, wat omslachtiger is dan een Secret.

**Combineren kan:** CSI voor de workloads met de strengste eis, ESO voor de rest.

## Keycloak

**Wat:** identity provider. Geen vault.

**Waar het wél hoort:** naast Argo CD als IdP (in plaats van de Dex-gebruiker uit
[gitops-lab G-11](../gitops-lab/LABS.md#g-11)), en als je veel applicaties hebt die OIDC/SSO nodig hebben.

**Waar het niet hoort:** applicatie-secrets. Stop geen database-wachtwoorden in Keycloak "omdat het er al is".

**De `Vault SPI`:** Keycloak kan zijn eigen secrets uit een externe kluis lezen (`file`, `keystore`, of een
eigen provider zoals HashiCorp Vault). Dat is de juiste rol: **Keycloak is een consument van je vault**, niet de
vault. In een Azure-omgeving: Keycloak's eigen secrets in Key Vault, via ESO of de SPI.

## SaaS-opties (kort)

| Optie | Sterk | Zwak |
|---|---|---|
| **Infisical** (open source, self-host of SaaS) | fijne UI, SDK's, redelijk compleet | jonger ecosysteem; self-host is weer een dienst |
| **Doppler** | eenvoud, goede DX | SaaS-only, kosten per seat |
| **1Password Connect** | vertrouwd voor mensen die 1Password gebruiken | minder "infrastructure secret"-gericht |
| **AWS/GCP Secret Manager + ESO** | zelfde patroon als Key Vault | zelfde beperkingen als Key Vault, maar in een andere cloud |

## Wat ik zou kiezen (en waarom)

| Situatie | Keuze |
|---|---|
| Alles in Azure, weinig beheer | **Key Vault + ESO** (dit lab) |
| Multi-cloud of dynamische DB-credentials | **OpenBao/Vault + ESO** |
| Klein team, repo moet self-contained | **Sealed Secrets**, of **SOPS + age** bij leesbare diffs |
| Strenge eis: secret nooit als K8s Secret | **CSI Driver** |
| Je hebt al een IdP nodig | **Keycloak als IdP**, niet als vault |

In alle gevallen geldt dezelfde architectuurles: je hebt altijd **één bootstrap-credential** en je moet kiezen
waar die staat ([CONCEPTS](CONCEPTS.md#bootstrap-credential)). Wie dat punt negeert, bouwt een systeem dat werkt
tot de eerste storing.

## Verder lezen

- [External Secrets Operator](https://external-secrets.io/) en de [providers](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [OpenBao](https://openbao.org/) · [Vault](https://developer.hashicorp.com/vault/docs)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) · [SOPS](https://github.com/getsops/sops)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Keycloak Vault SPI](https://www.keycloak.org/docs/latest/server_admin/#vault-spi)
