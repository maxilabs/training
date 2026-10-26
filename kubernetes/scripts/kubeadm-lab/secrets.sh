#!/usr/bin/env bash
# Secrets-lab (blok 9): External Secrets Operator + Azure Key Vault.
# Draait vanaf aristotle; kubectl-werk gaat via SSH naar cp1.
# Uitleg (wat en waarom): ../../secrets-lab/SCRIPTS.md
#
# Gebruik: ./secrets.sh <commando>
#   lz                 status van de landing zone (payload + Azure), read-only
#   install            ESO installeren via Argo CD en wachten op de CRD's
#   azure init         Key Vault + twee service principals + rollen + cluster-secrets
#   azure seed         voorbeeldsecrets in Key Vault zetten
#   stores             SecretStore/ClusterSecretStore renderen en toepassen
#   status             ESO-pods, stores en ExternalSecrets met hun condities
#   rotate             client-secret van beide SP's roteren (en het cluster bijwerken)
#   openbao            OpenBao in dev-modus + Vault-Store + voorbeeldsecret
#   debug <naam>       waarom is deze ExternalSecret niet Synced?
#   reset              alle lab-objecten weg (ESO blijft staan)
#   destroy            óók Key Vault (purge), SP's en namespaces weg
#
# De manifests staan in git; dit script doet alleen wat je niet declaratief kunt:
# Azure-resources, service principals en het bootstrap-credential in het cluster.
set -euo pipefail
cd "$(dirname "$0")"; source ./lab.env

SECRETS_DIR="$(cd ../../secrets-lab && pwd)"
GITOPS_DIR="$(cd ../../gitops-lab && pwd)"
STATE_DIR="${HOME}/.config/secrets-lab"
SP_ENV="${STATE_DIR}/azure-sp.env"

on_cp() { vm_ssh "$CP_NODE" "$@"; }
kc() { on_cp "kubectl $*"; }
azs() { az "$@" --subscription "$SECRETS_SUBSCRIPTION_ID"; }

# ── landing zone ──────────────────────────────────────────────────────────────
cmd_lz() {
  local payload="${SECRETS_DIR}/../..$(printf '')"
  log "landing zone voor het secrets-lab"
  printf 'subscription : %s\n' "$SECRETS_SUBSCRIPTION_ID"
  printf 'resource group: %s\n' "$SECRETS_RG"
  printf 'key vault     : %s\n' "$SECRETS_KV"
  echo
  azs group show --name "$SECRETS_RG" --query '{naam:name,locatie:location,status:properties.provisioningState}' -o table 2>&1 || true
  echo
  log "vnet en subnets (uit de vending machine)"
  azs network vnet list --resource-group "$SECRETS_RG" --query '[].{naam:name,ruimte:addressSpace.addressPrefixes[0]}' -o table 2>&1 || true
  echo
  log "key vault in deze resource group"
  azs keyvault list --resource-group "$SECRETS_RG" --query '[].{naam:name,rbac:properties.enableRbacAuthorization}' -o table 2>&1 || true
  echo
  log "payload in de solutions-repo"
  printf '%s\n' "landing-zone-vending-machine/payloads/k8s-secrets-dev-20261026.json"
}

# ── ESO installeren (via Argo CD) ─────────────────────────────────────────────
cmd_install() {
  log "ESO ${ESO_VERSION} als Argo CD-Application toepassen"
  vm_ssh "$CP_NODE" "kubectl apply --filename=-" < "${SECRETS_DIR}/platform/external-secrets.yaml"
  on_cp "kubectl apply --filename=-" < "${SECRETS_DIR}/platform/namespace.yaml"
  log "wachten tot de CRD's en pods er zijn"
  on_cp "for i in \$(seq 1 60); do
           kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1 && break; sleep 5; done
         kubectl --namespace=${ESO_NAMESPACE} rollout status deployment/external-secrets --timeout=300s || true
         kubectl --namespace=${ESO_NAMESPACE} get pods"
  log "Argo CD-status van de app"
  on_cp "kubectl --namespace=argocd get application external-secrets 2>/dev/null || true"
}

# ── Azure: Key Vault, service principals, rollen ──────────────────────────────
cmd_azure() {
  local action="${1:-init}"
  case "$action" in
    init)   azure_init ;;
    seed)   azure_seed ;;
    *) die "gebruik: ./secrets.sh azure init|seed" ;;
  esac
}

ensure_kv() {
  if azs keyvault show --name "$SECRETS_KV" >/dev/null 2>&1; then
    log "Key Vault ${SECRETS_KV} bestaat al"
    return
  fi
  log "Key Vault ${SECRETS_KV} aanmaken (RBAC-autorisatie, soft-delete 7 dagen)"
  azs keyvault create \
    --name "$SECRETS_KV" \
    --resource-group "$SECRETS_RG" \
    --location "$SECRETS_LOCATION" \
    --enable-rbac-authorization true \
    --retention-days 7 \
    --public-network-access Enabled \
    --query '{naam:name,rbac:properties.enableRbacAuthorization,purge:properties.enablePurgeProtection}' -o table
}

# maak_sp <naam> <rol> <doel-namespace>
# Bestaat de SP al? Dan een NIEUWE credential toevoegen (dat is precies roteren).
maak_sp() {
  local name="$1" role="$2"
  local app_id password
  app_id="$(az ad app list --display-name "$name" --query '[0].appId' -o tsv)"
  if [ -z "$app_id" ] || [ "$app_id" = "None" ]; then
    log "service principal ${name} aanmaken"
    az ad sp create-for-rbac --name "$name" --years 1 \
      --query '{appId:appId,password:password,tenant:tenant}' -o json > "${STATE_DIR}/${name}.json"
  else
    log "service principal ${name} bestaat (${app_id}): nieuwe client-secret"
    az ad app credential reset --id "$app_id" --append --years 1 \
      --query '{appId:appId,password:password,tenant:tenant}' -o json > "${STATE_DIR}/${name}.json"
  fi
  chmod 600 "${STATE_DIR}/${name}.json"

  local sp_object_id
  sp_object_id="$(az ad sp show --id "$(jq -r .appId "${STATE_DIR}/${name}.json")" --query id -o tsv)"
  log "rol '${role}' toekennen op ${SECRETS_KV} (scope: alleen deze vault)"
  if [ "$role" = "Key Vault Secrets User" ]; then
    # Lezen: secrets ophalen én de lijst kunnen zien (nodig voor dataFrom.find).
    azs role assignment create --role "$role" --assignee-object-id "$sp_object_id" \
      --assignee-principal-type ServicePrincipal \
      --scope "$(azs keyvault show --name "$SECRETS_KV" --query id -o tsv)" \
      --query '{rol:roleDefinitionName,scope:scope}' -o table 2>/dev/null || log "rol bestond al"
  else
    azs role assignment create --role "$role" --assignee-object-id "$sp_object_id" \
      --assignee-principal-type ServicePrincipal \
      --scope "$(azs keyvault show --name "$SECRETS_KV" --query id -o tsv)" \
      --query '{rol:roleDefinitionName,scope:scope}' -o table 2>/dev/null || log "rol bestond al"
  fi
}

# Zet de SP-gegevens in het cluster. Dit is het bootstrap-credential: het staat
# NIET in git, want het is zelf een secret. In productie vervang je dit door
# workload identity (AKS) of door Sealed Secrets/SOPS voor deze ene secret.
push_sp_secret() {
  local name="$1" target_ns="$2"
  local app_id password tenant
  app_id="$(jq -r .appId "${STATE_DIR}/${name}.json")"
  password="$(jq -r .password "${STATE_DIR}/${name}.json")"
  tenant="$(jq -r .tenant "${STATE_DIR}/${name}.json")"
  on_cp "kubectl --namespace=${target_ns} create secret generic ${name} \
           --from-literal=ClientID='${app_id}' \
           --from-literal=ClientSecret='${password}' \
           --dry-run=client --output=yaml | kubectl apply --filename=-" >/dev/null
  log "secret ${name} in namespace ${target_ns} bijgewerkt (ClientID ${app_id:0:8}…)"
}

azure_init() {
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  azs account show --query '{subscription:name,user:user.name}' -o table 2>&1 | head -3 || true
  ensure_kv

  maak_sp "sp-eso-k8s-reader" "Key Vault Secrets User"
  maak_sp "sp-eso-k8s-writer" "Key Vault Secrets Officer"

  # De ClusterSecretStore leest het auth-secret uit de ESO-namespace;
  # de namespaced SecretStore uit secrets-lab. Beide vullen we.
  push_sp_secret "sp-eso-k8s-reader" "$ESO_NAMESPACE"
  push_sp_secret "sp-eso-k8s-reader" "$SECRETS_NAMESPACE"
  push_sp_secret "sp-eso-k8s-writer" "$SECRETS_NAMESPACE"

  log "klaar. Nu: ./secrets.sh azure seed && ./secrets.sh stores"
}

azure_seed() {
  log "voorbeeldsecrets in ${SECRETS_KV} zetten"
  azs keyvault secret set --vault-name "$SECRETS_KV" --name db-password \
    --value "$(openssl rand -base64 24)" --query '{naam:name,versie:id}' -o table
  # Eén Key Vault-secret met JSON erin -> ESO 'extract' maakt er losse sleutels van.
  azs keyvault secret set --vault-name "$SECRETS_KV" --name app-config \
    --value "$(jq -nc --arg u appuser --arg p "$(openssl rand -base64 18)" \
      --arg k "$(openssl rand -hex 16)" --arg s "$(openssl rand -base64 18)" \
      '{username:$u,password:$p,api_key:$k,smtp_password:$s}')" \
    --query '{naam:name}' -o table
  azs keyvault secret set --vault-name "$SECRETS_KV" --name rotating-secret \
    --value "start-$(date +%s)" --query '{naam:name}' -o table
  log "secretnamen in de vault"
  azs keyvault secret list --vault-name "$SECRETS_KV" --query '[].name' -o tsv
}

# ── stores ────────────────────────────────────────────────────────────────────
cmd_stores() {
  local tenant kv_url
  tenant="$(azs account show --query tenantId -o tsv)"
  kv_url="https://${SECRETS_KV}.vault.azure.net"
  log "SecretStore en ClusterSecretStore renderen (tenant ${tenant:0:8}…, vault ${SECRETS_KV})"
  for f in secretstore-azurekv clustersecretstore-azurekv; do
    sed -e "s#<KV_NAME>#${SECRETS_KV}#g" -e "s#<TENANT_ID>#${tenant}#g" \
      "${SECRETS_DIR}/stores/${f}.yaml" | on_cp "kubectl apply --filename=-"
  done
  log "status van de stores (VALID is wat je wilt zien)"
  on_cp "kubectl --namespace=${SECRETS_NAMESPACE} get secretstore
         kubectl get clustersecretstore"
}

# ── status ────────────────────────────────────────────────────────────────────
cmd_status() {
  on_cp "kubectl --namespace=${ESO_NAMESPACE} get pods
         echo
         kubectl get clustersecretstore,clusterexternalsecret 2>/dev/null
         echo
         kubectl --namespace=${SECRETS_NAMESPACE} get secretstore 2>/dev/null
         echo
         kubectl --namespace=${SECRETS_NAMESPACE} get externalsecret 2>/dev/null || true
         echo
         kubectl --namespace=${SECRETS_NAMESPACE} get pushsecret 2>/dev/null || true"
}

cmd_debug() {
  local name="${1:-}"
  [ -n "$name" ] || die "gebruik: ./secrets.sh debug <naam-van-externalsecret>"
  on_cp "kubectl --namespace=${SECRETS_NAMESPACE} describe externalsecret ${name} | sed -n '/Conditions/,\$p'
         echo '--- events ---'
         kubectl --namespace=${SECRETS_NAMESPACE} get events --field-selector involvedObject.name=${name} --sort-by=.lastTimestamp | tail -5
         echo '--- ESO-log (laatste regels over deze ExternalSecret) ---'
         kubectl --namespace=${ESO_NAMESPACE} logs deploy/external-secrets --tail=200 | grep -i '${name}' | tail -5 || true"
}

# ── roteren ───────────────────────────────────────────────────────────────────
cmd_rotate() {
  log "client-secrets roteren (nieuwe credential, oude blijft tijdelijk geldig)"
  maak_sp "sp-eso-k8s-reader" "Key Vault Secrets User"
  maak_sp "sp-eso-k8s-writer" "Key Vault Secrets Officer"
  push_sp_secret "sp-eso-k8s-reader" "$ESO_NAMESPACE"
  push_sp_secret "sp-eso-k8s-reader" "$SECRETS_NAMESPACE"
  push_sp_secret "sp-eso-k8s-writer" "$SECRETS_NAMESPACE"
  log "ESO pakt het nieuwe secret bij de volgende reconciliatie; forceer hem:"
  on_cp "kubectl --namespace=${ESO_NAMESPACE} rollout restart deployment/external-secrets >/dev/null
         kubectl --namespace=${ESO_NAMESPACE} rollout status deployment/external-secrets --timeout=180s"
  cmd_status
}

# ── OpenBao (Azure-vrij alternatief) ─────────────────────────────────────────
cmd_openbao() {
  log "OpenBao (dev-modus) + Vault-Store plaatsen"
  on_cp "kubectl apply --filename=-" < "${SECRETS_DIR}/workloads/openbao/openbao.yaml"
  on_cp "kubectl --namespace=${SECRETS_NAMESPACE} rollout status deployment/openbao --timeout=180s"
  on_cp "kubectl --namespace=${SECRETS_NAMESPACE} create secret generic openbao-token \
           --from-literal=token=root --dry-run=client --output=yaml | kubectl apply --filename=-" >/dev/null
  # KV v2 is in dev-modus al gemount op 'secret/'.
  on_cp "kubectl --namespace=${SECRETS_NAMESPACE} exec deploy/openbao -- \
           env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=root \
           bao kv put secret/demo username=demo-user password=openbao-wachtwoord" >/dev/null
  on_cp "kubectl apply --filename=-" < "${SECRETS_DIR}/workloads/openbao/secretstore.yaml"
  on_cp "kubectl apply --filename=-" < "${SECRETS_DIR}/workloads/openbao/externalsecret.yaml"
  on_cp "kubectl --namespace=${SECRETS_NAMESPACE} get secretstore openbao
         kubectl --namespace=${SECRETS_NAMESPACE} get externalsecret openbao-demo"
}

# ── opruimen ──────────────────────────────────────────────────────────────────
cmd_reset() {
  log "lab-objecten opruimen (ESO en de vault blijven)"
  on_cp "kubectl delete externalsecret,clusterexternalsecret,pushsecret,secretstore --all \
           --namespace=${SECRETS_NAMESPACE} --ignore-not-found
         kubectl delete clustersecretstore azure-kv --ignore-not-found
         kubectl --namespace=${SECRETS_NAMESPACE} delete secret app-config db-password rotating \
           retain-demo delete-demo push-source openbao-demo --ignore-not-found"
  cmd_status
}

cmd_destroy() {
  log "alles weg: lab-namespaces, Key Vault (purge), service principals"
  on_cp "kubectl delete namespace ${SECRETS_NAMESPACE} --ignore-not-found --wait=false"
  azs keyvault delete --name "$SECRETS_KV" 2>/dev/null || log "vault bestond niet"
  azs keyvault purge --name "$SECRETS_KV" 2>/dev/null || log "purge niet nodig"
  for sp in sp-eso-k8s-reader sp-eso-k8s-writer; do
    local app_id
    app_id="$(az ad app list --display-name "$sp" --query '[0].appId' -o tsv)"
    [ -n "$app_id" ] && [ "$app_id" != "None" ] && az ad app delete --id "$app_id" && log "${sp} verwijderd"
  done
  rm -rf "$STATE_DIR"
  log "klaar. De landing zone (${SECRETS_RG}) blijft bestaan; die ruim je op met de vending machine:"
  printf '  gh workflow run deploy-landing-zone.yml -R maxilabs/solutions -f payload_file=k8s-secrets-dev-20261026.json -f action=destroy -f auto_approve=true\n'
}

case "${1:-help}" in
  lz)       cmd_lz ;;
  install)  cmd_install ;;
  azure)    shift; cmd_azure "$@" ;;
  stores)   cmd_stores ;;
  status)   cmd_status ;;
  rotate)   cmd_rotate ;;
  openbao)  cmd_openbao ;;
  debug)    shift; cmd_debug "$@" ;;
  reset)    cmd_reset ;;
  destroy)  cmd_destroy ;;
  help|--help|-h) awk 'NR>1 && /^set -euo/{exit} NR>1{sub(/^# ?/,""); print}' "$0" ;;
  *) die "onbekend commando: $1 (gebruik: help)" ;;
esac
