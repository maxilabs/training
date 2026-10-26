# SCRIPTS — wat doet secrets.sh?

`../scripts/kubeadm-lab/secrets.sh` is het enige script van dit lab. Het doet wat je **niet declaratief** kunt
doen: Azure-resources maken, service principals en rollen regelen, en het credential in het cluster zetten.

Alles wat wél declaratief kan — ExternalSecrets, stores, de demo-app, de ClusterExternalSecret — staat in git in
deze map.

> Draai het vanaf **aristotle** in `~/kubernetes/scripts/kubeadm-lab`. Het leest `lab.env` (net als de andere
> scripts) en voert kubectl-werk uit op **cp1** via `vm_ssh`.

## Overzicht

| Commando | Wat het doet | Handmatig equivalent |
|---|---|---|
| `lz` | status van de landing zone: subscription, RG, VNet, vault | `az group show`, `az network vnet list`, `az keyvault list` |
| `install` | ESO als Argo CD-Application toepassen + wachten op CRD's en pods | `kubectl apply -f secrets-lab/platform/external-secrets.yaml` |
| `azure init` | Key Vault + 2 service principals + rollen + cluster-secrets | de commando's hieronder |
| `azure seed` | voorbeeldsecrets in de vault (db-password, app-config, rotating-secret) | `az keyvault secret set` |
| `stores` | SecretStore/ClusterSecretStore renderen (`<KV_NAME>`, `<TENANT_ID>`) en toepassen | `sed` + `kubectl apply` |
| `status` | ESO-pods, stores, ExternalSecrets, PushSecrets | `kubectl get` |
| `rotate` | client-secrets van beide SP's roteren en het cluster bijwerken | `az ad app credential reset` |
| `openbao` | OpenBao in dev-modus + Vault-Store + voorbeeldsecret | `kubectl apply` + `bao kv put` |
| `debug <naam>` | conditie, events en ESO-log van één ExternalSecret | `kubectl describe`, `kubectl logs` |
| `reset` | lab-objecten weg, ESO en vault blijven | `kubectl delete externalsecret --all` |
| `destroy` | ook de vault (soft-delete) en de SP's weg | `az keyvault delete`, `az ad app delete` |

## install — waarom via Argo CD

```bash
kubectl apply -f secrets-lab/platform/external-secrets.yaml
```

Argo CD rendert de Helm-chart `external-secrets` (versie uit `lab.env`) zelf; er is geen `helm`-binary op de
node nodig. Twee `syncOptions` zijn essentieel:

| Optie | Waarom |
|---|---|
| `ServerSideApply=true` | de CRD's zijn te groot voor de client-side `last-applied`-annotatie |
| `SkipDryRunOnMissingResource=true` | de Application brengt zelf CRD's mee; de droge run faalt anders op "no matches for kind" |

En het AppProject moet het toestaan: de chart-repo in `sourceRepos`, de namespace in `destinations`, en
`ClusterRole`/`ClusterRoleBinding`/webhooks in `clusterResourceWhitelist`. Dat staat in
`gitops-lab/platform/project.yaml`.

## azure init — de kern

```bash
az keyvault create --name ml-kv-k8ssec-xxxx --resource-group ml-rg-k8s-secrets-dev \
  --location westeurope --enable-rbac-authorization true \
  --enable-purge-protection true --retention-days 7
```

| Detail | Waarom |
|---|---|
| `--enable-rbac-authorization true` | rollen in plaats van access policies: één model voor heel Azure |
| `--enable-purge-protection true` | **verplicht** door policy `Enforce-GR-KeyVault` (effect Deny) |
| unieke naam met suffix | purge protection houdt de naam 90 dagen vast na verwijderen |

Twee identiteiten, twee rollen:

```bash
az ad sp create-for-rbac --name sp-eso-k8s-reader --years 1    # Key Vault Secrets User
az ad sp create-for-rbac --name sp-eso-k8s-writer --years 1    # Key Vault Secrets Officer
az role assignment create --role "Key Vault Secrets User" \
  --assignee-object-id <sp-object-id> --assignee-principal-type ServicePrincipal \
  --scope <vault-id>
```

Daarna gaat het credential **niet** in git maar in het cluster:

```bash
kubectl -n external-secrets create secret generic azure-sp-reader \
  --from-literal=ClientID=... --from-literal=ClientSecret=...
```

Dat is het bootstrap-credential ([CONCEPTS](../secrets-lab/CONCEPTS.md#bootstrap-credential)). Het staat in
`~/.config/secrets-lab/*.json` met rechten 600, en als Secret in `external-secrets` en `secrets-lab`.

**Waarom ook jezelf een rol geven?** De maker van een RBAC-vault krijgt géén data-plane rechten. Zonder
`Key Vault Secrets Officer` kun je niet eens seeden. Dat is geen ongemak maar het ontwerp: toegang is altijd een
expliciete toewijzing.

## stores — waarom renderen

De manifests in `stores/` bevatten placeholders (`<KV_NAME>`, `<TENANT_ID>`), zodat er geen omgevingsspecifieke
waarden in git staan. `stores` vult ze in en past ze toe. Dezelfde truc als `envsubst`, maar met `sed`.

```bash
sed -e "s#<KV_NAME>#$KV#g" -e "s#<TENANT_ID>#$TENANT#g" stores/secretstore-azurekv.yaml | kubectl apply -f -
```

## rotate — de echte rotereoefening

```bash
az ad app credential reset --id <appId> --append --years 1   # nieuwe credential, oude blijft geldig
```

Daarna: Secret in het cluster bijwerken, ESO herstarten, en de **oude** credential pas intrekken als alles weer
synct. Roteren is toevoegen → uitrollen → intrekken, nooit "vervangen en hopen".

## destroy — en waarom purgen niet kan

```bash
az keyvault delete --name "$KV"       # soft-delete: 90 dagen herstelbaar
az keyvault purge  --name "$KV"       # ← faalt: purge protection staat aan
```

Dat is de policy, niet een fout. Gevolg: na `destroy` heb je een nieuwe vaultnaam nodig; vandaar de suffix.

## Snel opzoeken

| Vraag | Commando |
|---|---|
| Werkt ESO? | `./secrets.sh status` |
| Waarom is deze ExternalSecret niet klaar? | `./secrets.sh debug <naam>` |
| Wat staat er in de vault? | `az keyvault secret list --vault-name "$(cat ~/.config/secrets-lab/vault-name)"` |
| Welke rollen heeft de lezer? | `az role assignment list --assignee <appId> --scope <vault-id>` |
| Logt ESO een fout? | `kubectl -n external-secrets logs deploy/external-secrets --tail=50` |
| Is de webhook gezond? | `kubectl -n external-secrets get pods` + `kubectl get validatingwebhookconfiguration` |

## Bronnen

- [ESO installeren](https://external-secrets.io/latest/introduction/getting-started/)
- [Azure Key Vault-provider](https://external-secrets.io/latest/provider/azure-key-vault/)
- [Key Vault RBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [az keyvault](https://learn.microsoft.com/en-us/cli/azure/keyvault)
