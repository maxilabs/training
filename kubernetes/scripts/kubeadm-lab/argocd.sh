#!/usr/bin/env bash
# Argo CD voor blok 7 (GitOps). Draait vanaf aristotle, voert alles uit op cp1.
# Uitleg (wat en waarom): SCRIPTS.md en ../gitops-lab/SCRIPTS.md
#
# Gebruik: ./argocd.sh <commando>
#   install                  Argo CD installeren (namespace, manifests, NodePort, CLI)
#   status                   pods, applications, projects, Service
#   url | password           UI-adres / admin-wachtwoord
#   login                    argocd-CLI op cp1 inloggen (context 'lab')
#   bootstrap                de root-Application toepassen (app-of-apps start)
#   sso enable|disable       Dex met één lokale gebruiker + RBAC uit git testen
#   health-crd enable|disable  eigen health-check (Lua) voor de Widget-CRD
#   image-updater install|test  optioneel: argocd-image-updater (lab G-17)
#   cluster add|list|rm      tweede cluster registreren (lab G-15)
#   reset                    alle lab-apps en namespaces opruimen, Argo CD blijft
#   uninstall                Argo CD volledig verwijderen
#
# De manifests staan in git (../gitops-lab); dit script installeert alleen het gereedschap
# en doet de dingen die je niet declaratief kunt doen (NodePort, SSO-bootstrap, cluster toevoegen).
set -euo pipefail
cd "$(dirname "$0")"; source ./lab.env

GITOPS_DIR="$(cd ../../gitops-lab && pwd)"
ARGO_URL="https://$(node_ip "$CP_NODE"):${ARGOCD_NODEPORT_HTTPS}"

on_cp() { vm_ssh "$CP_NODE" "$@"; }
argo_password() {
  on_cp "kubectl --namespace=argocd get secret argocd-initial-admin-secret --output=jsonpath='{.data.password}' | base64 --decode"
}
# patch_cm <patch-json-bestand>: patch een ConfigMap in argocd met een lokaal JSON-bestand.
# De patch gaat via stdin naar cp1, zodat je geen lastige quoting in ssh-commando's krijgt.
patch_cm() {
  local cm="$1" file="$2"
  vm_ssh "$CP_NODE" "cat > /tmp/argocd-patch.json" < "$file"
  on_cp "kubectl --namespace=argocd patch configmap $cm --type=merge --patch-file=/tmp/argocd-patch.json"
}

# ── installeren ───────────────────────────────────────────────────────────────
cmd_install() {
  log "Argo CD ${ARGOCD_VERSION} installeren op $CP_NODE"
  # --server-side: de ApplicationSet- en CRD-manifests zijn te groot voor een gewone apply.
  on_cp "kubectl create namespace argocd --dry-run=client --output=yaml | kubectl apply --filename=-
         kubectl apply --namespace=argocd --server-side --force-conflicts \
           --filename=https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  log "wachten tot de componenten draaien"
  on_cp "kubectl --namespace=argocd rollout status statefulset/argocd-application-controller --timeout=600s
         for d in argocd-server argocd-repo-server argocd-redis argocd-dex-server \
                  argocd-notifications-controller argocd-applicationset-controller; do
           kubectl --namespace=argocd rollout status deployment/\$d --timeout=600s
         done"
  # De UI moet vanaf aristotle bereikbaar zijn zonder ssh-tunnel: daarom een NodePort.
  # Beide poorten wijzen naar 8080; de server doet zelf TLS.
  log "Service als NodePort exposen (https ${ARGOCD_NODEPORT_HTTPS}, http ${ARGOCD_NODEPORT_HTTP})"
  on_cp "kubectl --namespace=argocd patch service argocd-server --type=merge --patch='{
           \"spec\":{\"type\":\"NodePort\",\"ports\":[
             {\"name\":\"https\",\"port\":443,\"targetPort\":8080,\"nodePort\":${ARGOCD_NODEPORT_HTTPS}},
             {\"name\":\"http\",\"port\":80,\"targetPort\":8080,\"nodePort\":${ARGOCD_NODEPORT_HTTP}}]}}'"
  cmd_cli
  cmd_status
  printf '\nUI:       %s  (admin / %s)\n' "$ARGO_URL" "$(argo_password)"
  printf 'Volgende: ./argocd.sh login && ./argocd.sh bootstrap\n'
}

cmd_cli() {
  command -v argocd >/dev/null 2>&1 && { log "argocd-CLI staat lokaal al: $(argocd version --client --short 2>/dev/null || true)"; }
  if ! on_cp "command -v argocd >/dev/null 2>&1 && [ \"\$(argocd version --client --short 2>/dev/null | cut -d' ' -f2)\" = \"${ARGOCD_VERSION}\" ]"; then
    log "argocd-CLI ${ARGOCD_VERSION} installeren op $CP_NODE"
    on_cp "curl -fsSL --output=/tmp/argocd https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64
           sudo install -m 755 /tmp/argocd /usr/local/bin/argocd"
  fi
  on_cp "argocd version --client --short"
}

cmd_status() {
  on_cp "kubectl --namespace=argocd get pods --output=wide
         echo
         kubectl --namespace=argocd get applications
         echo
         kubectl --namespace=argocd get applicationsets,appprojects
         echo
         kubectl --namespace=argocd get service argocd-server"
}

cmd_url() { echo "$ARGO_URL"; }
cmd_password() { argo_password; }

cmd_login() {
  on_cp "argocd login $(node_ip "$CP_NODE"):${ARGOCD_NODEPORT_HTTPS} --insecure \
           --username admin --password '$(argo_password)' --name lab 2>&1 | tail -2"
}

cmd_bootstrap() {
  log "root-Application toepassen (app-of-apps): $(basename "$GITOPS_DIR")/bootstrap/root-app.yaml"
  vm_ssh "$CP_NODE" "kubectl apply --filename=-" < "$GITOPS_DIR/bootstrap/root-app.yaml"
  log "Argo CD doet de rest. Kijken: ./argocd.sh status"
}

# ── SSO (Dex) ─────────────────────────────────────────────────────────────────
cmd_sso() {
  local action="${1:-}"
  case "$action" in
    enable)
      log "Dex inschakelen: ${ARGOCD_SSO_EMAIL} via ${ARGO_URL}"
      local hash tmp
      hash="$(on_cp "argocd account bcrypt --password '${ARGOCD_SSO_PASSWORD}'")"
      [ -n "$hash" ] || die "bcrypt-hash maken mislukte"
      tmp="$(mktemp)"
      DEX_CONFIG="$(cat <<EOF
enablePasswordDB: true
connectors: []
oauth2:
  passwordConnector: local
  grantTypes:
    - authorization_code
    - refresh_token
    - password
staticPasswords:
  - email: ${ARGOCD_SSO_EMAIL}
    hash: ${hash}
    username: student
    userID: 6a1a8b1e-2f0c-4d3b-9a55-0f0d1b2c3d4e
EOF
)" URL="$ARGO_URL" python3 -c \
        'import json,os; print(json.dumps({"data":{"url":os.environ["URL"],"dex.config":os.environ["DEX_CONFIG"]}}))' > "$tmp"
      patch_cm argocd-cm "$tmp"; rm -f "$tmp"
      on_cp "kubectl --namespace=argocd rollout restart deployment/argocd-server deployment/argocd-dex-server
             kubectl --namespace=argocd rollout status deployment/argocd-server --timeout=300s
             kubectl --namespace=argocd rollout status deployment/argocd-dex-server --timeout=300s"
      log "test: Dex is bereikbaar en biedt de lokale login aan"
      sso_check || die "Dex werkt niet; controleer: kubectl --namespace=argocd logs deploy/argocd-dex-server"
      ;;
    disable)
      log "Dex-gebruiker en url weer weghalen"
      tmp="$(mktemp)"
      printf '%s' '{"data":{"url":"","dex.config":""}}' > "$tmp"
      patch_cm argocd-cm "$tmp"; rm -f "$tmp"
      on_cp "kubectl --namespace=argocd rollout restart deployment/argocd-server deployment/argocd-dex-server
             kubectl --namespace=argocd rollout status deployment/argocd-server --timeout=300s"
      ;;
    *) die "gebruik: ./argocd.sh sso enable|disable" ;;
  esac
}

sso_check() {
  local discovery secret token id_token i
  # De server is net herstart; een paar seconden geduld voordat Dex routes heeft.
  for i in $(seq 1 10); do
    discovery="$(curl -sk "$ARGO_URL/api/dex/.well-known/openid-configuration" || true)"
    printf '%s' "$discovery" | grep -q '"issuer"' && break
    sleep 3
  done
  if ! printf '%s' "$discovery" | grep -q '"issuer"'; then
    printf '%s\n' "$discovery" >&2
    return 1
  fi
  log "Dex actief: $(printf '%s' "$discovery" | python3 -c 'import json,sys; print(json.load(sys.stdin)["issuer"])')"
  # De client-id 'argo-cd' maakt Argo CD zelf aan; het secret staat in de gegenereerde Dex-config.
  secret="$(on_cp "kubectl --namespace=argocd exec deploy/argocd-dex-server -c dex -- \
    awk '/^- id: argo-cd\$/{f=1} f && /secret:/{print \$2; exit}' /tmp/dex.yaml" 2>/dev/null | tr -d '\r')"
  [ -n "$secret" ] || { log "let op: client-secret niet gevonden; UI-login test je in de browser"; return 0; }

  for i in $(seq 1 5); do
    token="$(curl -sk --request POST "$ARGO_URL/api/dex/token" \
      --data-urlencode "grant_type=password" \
      --data-urlencode "username=${ARGOCD_SSO_EMAIL}" \
      --data-urlencode "password=${ARGOCD_SSO_PASSWORD}" \
      --data-urlencode "client_id=argo-cd" \
      --data-urlencode "client_secret=${secret}" \
      --data-urlencode "scope=openid email" || true)"
    id_token="$(printf '%s' "$token" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id_token",""))
except Exception: print("")' 2>/dev/null)"
    [ -n "$id_token" ] && break
    sleep 3
  done
  if [ -n "$id_token" ]; then
    log "token ontvangen voor ${ARGOCD_SSO_EMAIL}: SSO-login werkt (open de UI, kies 'Log in via Dex')"
    # Laat meteen zien welke identiteit en groepen Argo CD ziet: dat is wat de RBAC-regels matchen.
    local userinfo
    userinfo="$(curl -sk --header "Authorization: Bearer ${id_token}" "$ARGO_URL/api/v1/session/userinfo")"
    printf '%s' "$userinfo" | grep -q '"loggedIn":true' && \
      log "identiteit volgens de API: $(printf '%s' "$userinfo" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("username"), d.get("groups"))')"
  else
    log "let op: geen token via de password-grant; test de login in de browser"
    printf '%s\n' "$token" >&2
  fi
}

# ── eigen health-check (Lua) ──────────────────────────────────────────────────
cmd_health_crd() {
  local action="${1:-}" tmp
  case "$action" in
    enable)
      log "Lua-health-check voor Widgets toevoegen aan argocd-cm"
      tmp="$(mktemp)"
      LUA='hs = {}
if obj.status ~= nil and obj.status.ready == true then
  hs.status = "Healthy"
  hs.message = "Widget is ready"
else
  hs.status = "Progressing"
  hs.message = "Wacht tot status.ready = true"
end
return hs' python3 -c \
        'import json,os; print(json.dumps({"data":{"resource.customizations.health.labs.maxilabs.dev_Widget":os.environ["LUA"]}}))' > "$tmp"
      patch_cm argocd-cm "$tmp"; rm -f "$tmp"
      on_cp "kubectl --namespace=argocd rollout restart statefulset/argocd-application-controller
             kubectl --namespace=argocd rollout status statefulset/argocd-application-controller --timeout=300s"
      log "Nu: kubectl apply -f $ARGOCD_GITOPS_PATH/clusters/lab/optional/health-crd.yaml"
      ;;
    disable)
      log "health-check weghalen"
      on_cp "kubectl --namespace=argocd patch configmap argocd-cm --type=json \
               --patch='[{\"op\":\"remove\",\"path\":\"/data/resource.customizations.health.labs.maxilabs.dev_Widget\"}]' || true
             kubectl --namespace=argocd rollout restart statefulset/argocd-application-controller"
      ;;
    *) die "gebruik: ./argocd.sh health-crd enable|disable" ;;
  esac
}

# ── image updater (optioneel) ─────────────────────────────────────────────────
cmd_image_updater() {
  local action="${1:-}"
  case "$action" in
    install)
      log "argocd-image-updater ${ARGOCD_IMAGE_UPDATER_VERSION} installeren"
      on_cp "kubectl apply --namespace=argocd --server-side --force-conflicts \
               --filename=https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/${ARGOCD_IMAGE_UPDATER_VERSION}/config/install.yaml
             kubectl --namespace=argocd rollout status deployment/argocd-image-updater-controller --timeout=300s"
      log "Image updater draait; configureer hem met een ImageUpdater-CR of de oude annotaties (lab G-17)"
      ;;
    test)
      log "Welke tag zou de updater kiezen? (alleen kijken, niets schrijven)"
      on_cp "kubectl --namespace=argocd exec deploy/argocd-image-updater-controller -- \
               argocd-image-updater test nginxinc/nginx-unprivileged --update-strategy semver 2>&1 | tail -12"
      ;;
    *) die "gebruik: ./argocd.sh image-updater install|test" ;;
  esac
}

# ── tweede cluster registreren ────────────────────────────────────────────────
cmd_cluster() {
  local action="${1:-}"
  case "$action" in
    add)
      # Geen tweede cluster bij de hand? We registreren dezelfde API-server onder een andere
      # URL (het node-IP in plaats van kubernetes.default.svc). Argo CD ziet dat als een
      # apart cluster, dus alle mechanica (cluster-secret, service account, destination)
      # is identiek aan een echt tweede cluster.
      log "cluster 'lab-external' registreren (server https://$(node_ip "$CP_NODE"):6443)"
      on_cp "sudo cp /etc/kubernetes/admin.conf /tmp/argocd-external.conf
             sudo chown \$(id -un) /tmp/argocd-external.conf
             sed -i 's#server: https://.*#server: https://$(node_ip "$CP_NODE"):6443#' /tmp/argocd-external.conf
             argocd cluster add kubernetes-admin@kubernetes --name lab-external \
               --kubeconfig /tmp/argocd-external.conf --upsert --yes 2>&1 | tail -2
             argocd cluster list"
      log "Vergeet niet de destination in platform/project.yaml te zetten (git + push)"
      ;;
    list) on_cp "argocd cluster list" ;;
    rm)   on_cp "argocd cluster rm lab-external --yes" ;;
    *) die "gebruik: ./argocd.sh cluster add|list|rm" ;;
  esac
}

# ── opruimen ──────────────────────────────────────────────────────────────────
cmd_reset() {
  log "alle lab-apps en namespaces opruimen (Argo CD zelf blijft)"
  on_cp "kubectl --namespace=argocd delete applications --all --cascade=orphan --ignore-not-found
         kubectl --namespace=argocd delete applicationset guests --ignore-not-found
         kubectl delete namespace web-lab web-prod helm-demo lab-waves lab-waves-fail \
           guests-dev guests-stg guests-prod lab-observability lab-health --ignore-not-found --wait=false
         kubectl --namespace=argocd get applications"
}

cmd_uninstall() {
  log "Argo CD verwijderen (namespace argocd inclusief CRD's)"
  on_cp "kubectl delete namespace argocd --ignore-not-found
         kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io \
           imageupdaters.argocd-image-updater.argoproj.io --ignore-not-found"
}

case "${1:-help}" in
  install)        cmd_install ;;
  status)         cmd_status ;;
  url)            cmd_url ;;
  password)       cmd_password ;;
  login)          cmd_login ;;
  bootstrap)      cmd_bootstrap ;;
  sso)            shift; cmd_sso "$@" ;;
  health-crd)     shift; cmd_health_crd "$@" ;;
  image-updater)  shift; cmd_image_updater "$@" ;;
  cluster)        shift; cmd_cluster "$@" ;;
  reset)          cmd_reset ;;
  uninstall)      cmd_uninstall ;;
  help|--help|-h) awk 'NR>1 && /^set -euo/{exit} NR>1{sub(/^# ?/,""); print}' "$0" ;;
  *) die "onbekend commando: $1 (gebruik: help)" ;;
esac
