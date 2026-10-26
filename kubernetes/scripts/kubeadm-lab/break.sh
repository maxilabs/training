#!/usr/bin/env bash
# Fase 3: troubleshooting-oefeningen (L-19 t/m L-22). Maakt bewust iets kapot; jij zoekt en herstelt het.
# Uitleg (wat en waarom): SCRIPTS.md
# Start vanaf een werkend cluster MET CNI (bijv. ./snapshot.sh revert calico-ready).
#
# Gebruik:
#   ./break.sh list                 overzicht (alleen titels, geen oplossingen)
#   ./break.sh <nr>                 scenario <nr> starten
#   ./break.sh random               willekeurig scenario; je ziet alleen het symptoom
#   ./break.sh check <nr>           controleren of je het hebt opgelost
#   ./break.sh hint <nr>            een hint (geen oplossing)
#   ./break.sh restore <nr>         noodknop: zet de originele situatie terug
# Zwaar vast? ./snapshot.sh revert calico-ready
#
# ⚠  SPOILERWAARSCHUWING: de functies do_break en do_restore hieronder laten precies zien
#    WAT er kapot gaat. Wil je echt oefenen, lees dan alleen tot TITLES/HINTS.
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# In .break/ (op aristotle) staat per actief scenario een bestandje; zo weet 'list'
# welke scenario's nog openstaan.
STATE_DIR=".break"; mkdir -p "$STATE_DIR"
CP="$CP_NODE"; W1="w1"; W2="w2"
# on <node> <cmd>: commando op een node | k <args>: kubectl op cp1
on() { local n="$1"; shift; vm_ssh "$n" "$@"; }
k()  { on "$CP" "kubectl $*"; }
BK="/root/break-backup"   # backups van originele bestanden op de nodes

# backup_file <node> <bestand>: kopie van het origineel naar /root/break-backup,
#   maar alleen de EERSTE keer (anders zou een tweede run de kapotte versie bewaren).
# restore_file <node> <bestand>: die kopie terugzetten (gebruikt door 'restore').
# ns_app: namespace 'break' aanmaken als die nog niet bestaat
#   (dry-run + apply = idempotent: geen fout als hij er al is).
backup_file() { on "$1" "sudo mkdir -p $BK && sudo test -f $BK/$(basename "$2") || sudo cp -a $2 $BK/"; }
restore_file() { on "$1" "sudo cp -a $BK/$(basename "$2") $2"; }
ns_app() { on "$CP" "kubectl create namespace break --dry-run=client --output=yaml | kubectl apply --filename=- >/dev/null"; }

# Titels = het symptoom dat je ziet (zoals een examenvraag), geen oorzaak.
# Index 0 is leeg, zodat scenario 1 op plek 1 staat.
TITLES=(
  ""                                                              # 0 ongebruikt
  "Control plane: kubectl werkt niet meer"                         # 1
  "Node w1 is NotReady"                                            # 2
  "Node w2 is NotReady (andere oorzaak)"                           # 3
  "Nieuwe Pods blijven Pending"                                    # 4
  "App 'shop' start niet (1)"                                      # 5
  "App 'api' herstart steeds"                                      # 6
  "App 'worker' start niet (2)"                                    # 7
  "Service 'web' geeft geen antwoord (1)"                          # 8
  "Service 'web2' geeft geen antwoord (2)"                         # 9
  "Servicenamen resolven niet meer"                                # 10
)
# Hints wijzen een richting aan (welk commando, welke laag), niet de oplossing.
HINTS=(
  ""
  "Static Pods staan in /etc/kubernetes/manifests. Zonder API-server: sudo crictl ps -a en sudo crictl logs, of /var/log/pods."
  "Begin op de node zelf: systemctl status kubelet, journalctl -u kubelet."
  "De kubelet draait misschien wel, maar waar start hij containers mee? systemctl status van de runtime."
  "Wie bepaalt op welke node een Pod komt? Kijk in kube-system en in de manifests op cp1."
  "kubectl describe pod: lees de Events onderaan."
  "kubectl logs --previous en kijk naar command/args van de container."
  "kubectl describe pod: de status noemt een object dat ontbreekt."
  "kubectl get endpointslices --selector=kubernetes.io/service-name=web: is er iets? Vergelijk labels."
  "Endpoints zijn er wel. Klopt de poort waar de Service naartoe stuurt?"
  "Draait er iets in kube-system dat DNS levert? Hoeveel replicas?"
)

# ── do_break <nr>: maakt scenario <nr> kapot (SPOILER) ────────────────────────
# Wijzigt het een bestand op een node, dan eerst backup_file. Daarna komt er een
# tijdstempel in .break/<nr>, zodat 'list' het scenario als [actief] toont.
do_break() {
  case "$1" in
    1) F=/etc/kubernetes/manifests/kube-apiserver.yaml; backup_file "$CP" "$F"
       on "$CP" "sudo sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2380#' $F" ;;
    2) on "$W1" "sudo systemctl stop kubelet && sudo systemctl disable kubelet" >/dev/null 2>&1 ;;
    3) on "$W2" "sudo systemctl stop containerd" ;;
    4) F=/etc/kubernetes/manifests/kube-scheduler.yaml; backup_file "$CP" "$F"
       on "$CP" "sudo sed -i -E 's#(image: .*kube-scheduler):.*#\\1:v0.0.0-bestaat-niet#' $F" ;;
    5) ns_app; k "--namespace=break create deployment shop --image=nginx:9.99-bestaat-niet" ;;
    6) ns_app; k "--namespace=break create deployment api --image=busybox:1.36 -- /bin/sh -c 'echo start; exit 1'" ;;
    7) ns_app; cat <<'EOF' | on "$CP" "kubectl apply --filename=-"
apiVersion: v1
kind: Pod
metadata: {name: worker, namespace: break}
spec:
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sleep", "3600"]
    envFrom: [{configMapRef: {name: worker-config}}]
EOF
       ;;
    8) ns_app; k "--namespace=break create deployment web --image=nginx:1.27"
       k "--namespace=break expose deployment web --port=80"
       k "--namespace=break patch service web --patch='{\"spec\":{\"selector\":{\"app\":\"webb\"}}}'" ;;
    9) ns_app; k "--namespace=break create deployment web2 --image=nginx:1.27"
       k "--namespace=break expose deployment web2 --port=80 --target-port=8080" ;;
    10) k "--namespace=kube-system scale deployment coredns --replicas=0" ;;
    *) die "onbekend scenario: $1" ;;
  esac
  date +%s >"$STATE_DIR/$1"
}

# ── do_check <nr>: is het ECHT opgelost? ──────────────────────────────────────
# Test het gedrag, niet jouw aanpak: werkt kubectl weer, is de node Ready, wordt
# een nieuwe Pod ingepland, geeft de Service antwoord, werkt DNS? Er zijn dus
# meerdere goede oplossingen mogelijk. ok=1 tenzij een test faalt.
do_check() {
  local ok=1
  case "$1" in
    1) k "get nodes" >/dev/null 2>&1 || ok=0 ;;
    2) k "get node $W1 --no-headers" | grep -q ' Ready ' || ok=0 ;;
    3) k "get node $W2 --no-headers" | grep -q ' Ready ' || ok=0 ;;
    4) k "run sched-test --image=nginx:1.27 --restart=Never" >/dev/null 2>&1 || true; sleep 15
       k "get pod sched-test --output=jsonpath='{.spec.nodeName}'" | grep -q . || ok=0
       k "delete pod sched-test --now" >/dev/null 2>&1 || true ;;
    5) k "--namespace=break rollout status deployment/shop --timeout=60s" >/dev/null 2>&1 || ok=0 ;;
    6) k "--namespace=break rollout status deployment/api --timeout=60s" >/dev/null 2>&1 || ok=0 ;;
    7) k "--namespace=break get pod worker --output=jsonpath='{.status.phase}'" | grep -q Running || ok=0 ;;
    8) k "run t8 --image=busybox:1.36 --rm --stdin --restart=Never --namespace=break -- wget -qO- -T 3 web" 2>/dev/null | grep -qi nginx || ok=0 ;;
    9) k "run t9 --image=busybox:1.36 --rm --stdin --restart=Never --namespace=break -- wget -qO- -T 3 web2" 2>/dev/null | grep -qi nginx || ok=0 ;;
    10) k "run t10 --image=busybox:1.36 --rm --stdin --restart=Never -- nslookup kubernetes.default" 2>/dev/null | grep -q 'Address' || ok=0 ;;
    *) die "onbekend scenario: $1" ;;
  esac
  if [ $ok -eq 1 ]; then log "Scenario $1: OPGELOST"; rm -f "$STATE_DIR/$1"; else echo "Scenario $1: nog niet opgelost."; fi
}

# ── do_restore <nr>: noodknop, zet de originele situatie terug (SPOILER) ───────
do_restore() {
  case "$1" in
    1) restore_file "$CP" /etc/kubernetes/manifests/kube-apiserver.yaml ;;
    2) on "$W1" "sudo systemctl enable --now kubelet" ;;
    3) on "$W2" "sudo systemctl start containerd" ;;
    4) restore_file "$CP" /etc/kubernetes/manifests/kube-scheduler.yaml ;;
    5|6|7|8|9) k "delete namespace break --wait=false" ;;
    10) k "--namespace=kube-system scale deployment coredns --replicas=2" ;;
    *) die "onbekend scenario: $1" ;;
  esac
  rm -f "$STATE_DIR/$1"; log "Scenario $1 teruggezet."
}

# ── Hoofdprogramma ────────────────────────────────────────────────────────────
# $1 = actie (list/random/check/hint/restore) of direct een scenarionummer; $2 = nummer.
# random: kiest een nummer tussen 1 en het aantal scenario's en toont alleen het symptoom.
ACTION="${1:-list}"; N="${2:-}"
case "$ACTION" in
  list)    for i in $(seq 1 $((${#TITLES[@]}-1))); do printf '%2d  %s%s\n' "$i" "${TITLES[$i]}" "$([ -f "$STATE_DIR/$i" ] && echo '   [actief]')"; done ;;
  random)  i=$(( (RANDOM % (${#TITLES[@]}-1)) + 1 )); do_break "$i"
           echo "Er is iets kapot. Symptoom: ${TITLES[$i]}"; echo "Controleer later met: ./break.sh check $i" ;;
  check)   [ -n "$N" ] || die "./break.sh check <nr>"; do_check "$N" ;;
  hint)    [ -n "$N" ] || die "./break.sh hint <nr>"; echo "Hint $N: ${HINTS[$N]}" ;;
  restore) [ -n "$N" ] || die "./break.sh restore <nr>"; do_restore "$N" ;;
  [0-9]*)  do_break "$ACTION"; echo "Scenario $ACTION gestart. Symptoom: ${TITLES[$ACTION]}"
           echo "Los het op vanaf cp1 (en de nodes), controleer met: ./break.sh check $ACTION" ;;
  *)       sed -n '2,13p' "$0"; exit 1 ;;
esac
