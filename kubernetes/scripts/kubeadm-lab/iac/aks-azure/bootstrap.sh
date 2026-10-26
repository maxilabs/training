#!/usr/bin/env bash
# Eenmalige Azure-voorbereiding voor scenario B ("kip-en-ei": Terraform heeft een state-opslag en een
# identiteit nodig voordat het zelf iets kan). Draai dit één keer lokaal, na 'az login'.
# Uitleg: INIT.md (blok 8) en CONCEPTS.md#remote-state, CONCEPTS.md#oidc-federatie.
#
# Gebruik:  GH_REPO=<account>/<repo> ./iac/aks-azure/bootstrap.sh
# Maakt:
#   rg-k8s-tfstate  + storage account + container 'tfstate'   (de Terraform-state)
#   rg-k8s-lab                                                (waar AKS in komt)
#   app-registratie 'gh-k8s-lab' + service principal
#   federated credentials voor GitHub: pull requests (plan) en environment 'azure' (apply/destroy)
#   rollen: Contributor alleen op rg-k8s-lab (niets op subscriptieniveau: least privilege)
#           en Storage Blob Data Contributor alleen op de state-container
set -euo pipefail

: "${GH_REPO:?Zet GH_REPO=<account>/<repo>, bijv. GH_REPO=tobias/kubeadm-lab}"
LOCATION="${LOCATION:-westeurope}"
RG_STATE="rg-k8s-tfstate"
RG_LAB="rg-k8s-lab"
APP_NAME="gh-k8s-lab"
# Storage-accountnamen moeten wereldwijd uniek zijn: 3-24 kleine letters/cijfers.
SA="${SA:-sttfstate$(az account show --query id -o tsv | tr -d '-' | cut -c1-12)}"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "== subscriptie $SUB_ID, tenant $TENANT_ID, regio $LOCATION, storage account $SA"

echo "== resource providers registreren (AKS en de Flux-extensie)"
az provider register --namespace Microsoft.ContainerService --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait

echo "== resource groups"
az group create --name "$RG_STATE" --location "$LOCATION" --tags purpose=cka-lab -o none
az group create --name "$RG_LAB"   --location "$LOCATION" --tags purpose=cka-lab -o none

echo "== storage voor de state (geen publieke blobs, geen shared keys: alleen Entra ID)"
az storage account create --name "$SA" --resource-group "$RG_STATE" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false -o none
# container-rm = via de beheer-API (ARM); dan heb jij zelf geen data-rol op de storage nodig
az storage container-rm create --storage-account "$SA" --resource-group "$RG_STATE" --name tfstate -o none

echo "== app-registratie + service principal voor GitHub Actions"
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
[ -n "$APP_ID" ] || APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
az ad sp show --id "$APP_ID" -o none 2>/dev/null || az ad sp create --id "$APP_ID" -o none

echo "== federated credentials (subject moet EXACT kloppen, anders faalt het inloggen pas in de workflow)"
fic() {  # fic <naam> <subject>
  az ad app federated-credential list --id "$APP_ID" --query "[?name=='$1'] | length(@)" -o tsv | grep -q '^1$' && return
  az ad app federated-credential create --id "$APP_ID" -o none --parameters "{
    \"name\": \"$1\", \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$2\", \"audiences\": [\"api://AzureADTokenExchange\"]}"
}
fic gh-pull-request "repo:${GH_REPO}:pull_request"       # plan op een PR
fic gh-env-azure    "repo:${GH_REPO}:environment:azure"   # apply/destroy via environment 'azure'

echo "== rollen (least privilege: alleen de lab-RG en de state-container)"
SCOPE_RG="$(az group show --name "$RG_LAB" --query id -o tsv)"
SCOPE_STATE="$(az storage account show --name "$SA" --resource-group "$RG_STATE" --query id -o tsv)/blobServices/default/containers/tfstate"
az role assignment create --assignee "$APP_ID" --role Contributor --scope "$SCOPE_RG" -o none
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "$SCOPE_STATE" -o none

cat <<EOF

Klaar. Zet in GitHub (repo → Settings → Secrets and variables → Actions → Variables):
  AZURE_CLIENT_ID        = $APP_ID
  AZURE_TENANT_ID        = $TENANT_ID
  AZURE_SUBSCRIPTION_ID  = $SUB_ID
  TFSTATE_STORAGE_ACCOUNT= $SA
  GITOPS_REPO_URL        = https://github.com/<account>/k8s-lab-gitops
En maak een environment 'azure' (Settings → Environments), eventueel met 'Required reviewers'.
Of in één keer met de GitHub CLI:
  for kv in AZURE_CLIENT_ID=$APP_ID AZURE_TENANT_ID=$TENANT_ID AZURE_SUBSCRIPTION_ID=$SUB_ID TFSTATE_STORAGE_ACCOUNT=$SA; do gh variable set "\${kv%%=*}" --repo "$GH_REPO" --body "\${kv#*=}"; done
EOF
