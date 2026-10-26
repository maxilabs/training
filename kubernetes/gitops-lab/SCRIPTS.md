# SCRIPTS — wat doet argocd.sh, en waarom?

`../scripts/kubeadm-lab/argocd.sh` is het enige script van dit lab. Het doet precies twee soorten dingen:

1. **Het gereedschap neerzetten** — Argo CD installeren, de UI bereikbaar maken, de CLI op cp1 zetten.
2. **De kip-en-ei-stappen** — dingen die je niet declaratief kunt doen: een NodePort, een eerste bootstrap, SSO
   aanzetten, een tweede cluster registreren.

Alles wat wél declaratief kan (Applications, AppProject, RBAC, notificaties, workloads) staat in git in deze map.
Dat onderscheid is de kern van het lab: **git is de bron, het script is alleen de handen.**

> Draai het vanaf **aristotle** in `~/kubernetes/scripts/kubeadm-lab`. Het leest `lab.env` (net als de andere
> scripts) en voert alles uit op **cp1** via `vm_ssh`.

## Overzicht

| Commando | Wat het doet | Handmatig equivalent |
|---|---|---|
| `install` | namespace + `install.yaml` (server-side) + wachten + NodePort + CLI | de commando's hieronder |
| `status` | pods, applications, applicationsets, projects, Service | `kubectl -n argocd get pods,applications` |
| `url` / `password` | UI-adres / admin-wachtwoord | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| `login` | `argocd login` met context `lab` | `argocd login 192.168.122.11:30443 --insecure` |
| `bootstrap` | de root-Application toepassen | `kubectl apply -f ../../gitops-lab/bootstrap/root-app.yaml` |
| `sso enable\|disable` | Dex met één lokale gebruiker + `url` in `argocd-cm` | patch van `argocd-cm`, herstart server en Dex |
| `health-crd enable\|disable` | Lua-health-check voor de Widget-CRD | patch van `argocd-cm`, herstart application-controller |
| `image-updater install\|test` | argocd-image-updater + een registry-query | `kubectl apply -f .../config/install.yaml`, daarna `/manager test` |
| `cluster add\|list\|rm` | tweede cluster registreren | `argocd cluster add <context> --name lab-external` |
| `reset` | lab-apps + namespaces weg, Argo CD blijft | `kubectl -n argocd delete applications --all` + namespaces |
| `uninstall` | namespace `argocd` + CRD's weg | `kubectl delete namespace argocd` |

## install — waarom deze stappen

```bash
kubectl create namespace argocd
kubectl apply --namespace=argocd --server-side --force-conflicts \
  --filename=https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml
```

| Detail | Waarom |
|---|---|
| `--server-side` | de ApplicationSet- en CRD-manifests zijn groter dan de `last-applied-configuration`-annotatie aankan; client-side apply faalt met "Too long" |
| `--force-conflicts` | conflicten met velden die het cluster al beheert (herinstallatie) niet laten blokkeren |
| versie vastgezet in `lab.env` | het lab moet morgen hetzelfde doen; `stable` verandert onder je voeten |

Daarna wacht het script op de zeven componenten:

```bash
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s
kubectl -n argocd rollout status deployment/argocd-server --timeout=600s
# ... repo-server, redis, dex-server, notifications-controller, applicationset-controller
```

De UI bereikbaar maken zonder ssh-tunnel:

```bash
kubectl --namespace=argocd patch service argocd-server --type=merge --patch='{
  "spec":{"type":"NodePort","ports":[
    {"name":"https","port":443,"targetPort":8080,"nodePort":30443},
    {"name":"http","port":80,"targetPort":8080,"nodePort":30080}]}}'
```

Beide poorten wijzen naar **8080**: de `argocd-server` doet zelf TLS, dus `https://…:30443` is de echte UI en
`http://…:30080` verwijst door.

En de CLI, zodat je op cp1 kunt werken zonder je laptop:

```bash
curl -fsSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.5.6/argocd-linux-amd64
sudo install -m 755 /tmp/argocd /usr/local/bin/argocd
```

## sso — waarom dit een patch is en geen manifest

SSO-instellingen staan in `argocd-cm`, en dat is óók de ConfigMap waar Argo CD zelf sleutels in zet (`url`,
`dex.config`, health-checks, `timeout.reconciliation`). Een Application die die ConfigMap volledig beheert,
overschrijft wat Argo CD zelf nodig heeft. Daarom:

- **wel** in git (via de Application `platform`): `AppProject`, `argocd-rbac-cm`, `argocd-notifications-cm`.
  Die zijn volledig van jou.
- **niet** in git: `argocd-cm`. Dat is een patch-stap in het script, met uitleg erbij.

Het script doet:

```bash
HASH=$(argocd account bcrypt --password "$ARGOCD_SSO_PASSWORD")   # bcrypt-hash, client-side
# argocd-cm:
#   url: https://192.168.122.11:30443
#   dex.config: enablePasswordDB + staticPasswords + connectors: []
kubectl -n argocd rollout restart deployment/argocd-server deployment/argocd-dex-server
```

Twee details die je anders een uur kosten:

| Symptoom | Oorzaak |
|---|---|
| `malformed Dex configuration found` | `dex.config` zonder `connectors`-sleutel; Argo CD eist dat veld, ook als je alleen de password-DB gebruikt |
| `unknown connector type "local"` | je probeerde de connector zelf te declareren; die ontstaat pas door `enablePasswordDB: true` |

De controle in het script is een echte login: het haalt een token op bij `/api/dex/token` en vraagt daarna
`/api/v1/session/userinfo` op. Zo zie je meteen welke identiteit en groepen Argo CD ziet — dat is wat je
RBAC-regels matchen.

## health-crd — een eigen oordeel over "gezond"

```bash
kubectl -n argocd patch configmap argocd-cm --type=merge --patch-file=/dev/stdin <<'JSON'
{"data":{"resource.customizations.health.labs.maxilabs.dev_Widget":"hs = {}\n..."}}
JSON
```

De sleutel is altijd `<group>_<Kind>`. Zonder deze regel is elke custom resource `Healthy` zodra hij bestaat —
ook als de controller niets doet. Dat is de stille faalmodus die je in G-16 ziet.

## cluster add — dezelfde API-server, andere URL

```bash
sudo cp /etc/kubernetes/admin.conf /tmp/argocd-external.conf
sed -i 's#server: https://.*#server: https://192.168.122.11:6443#' /tmp/argocd-external.conf
argocd cluster add kubernetes-admin@kubernetes --name lab-external \
  --kubeconfig /tmp/argocd-external.conf --upsert --yes
```

Waarom niet `127.0.0.1`? Omdat de Argo CD-pods op w1/w2 draaien: die kunnen jouw localhost niet bereiken. Het
node-IP wel. Argo CD ziet `https://192.168.122.11:6443` als een ánder cluster dan `kubernetes.default.svc`,
dus je oefent de volledige mechanica (cluster-secret, `argocd-manager`-serviceaccount, destination in het project)
zonder tweede cluster.

## reset en uninstall

```bash
# reset: alleen de lab-apps
kubectl -n argocd delete applications --all --cascade=orphan
kubectl -n argocd delete applicationset guests
kubectl delete namespace web-lab web-prod helm-demo lab-waves lab-waves-fail \
  guests-dev guests-stg guests-prod lab-observability lab-health

# uninstall: alles, inclusief CRD's
kubectl delete namespace argocd
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

`--cascade=orphan` laat de resources staan en ruimt alleen de Applications op: sneller en zonder
finalizer-verrassingen. De namespaces gaan daarna expliciet weg.

`uninstall` doet het in deze volgorde, en dat is niet toevallig:

```bash
# 1. finalizers van de Applications weghalen (anders blijft de namespace 'Terminating')
kubectl -n argocd get applications -o name | while read -r app; do
  kubectl -n argocd patch "$app" --type=merge -p '{"metadata":{"finalizers":null}}'
done
# 2. de namespace
kubectl delete namespace argocd
# 3. de CRD's
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

Zonder stap 1 verdwijnt de controller voordat hij de `resources-finalizer` kan afhandelen: de namespace blijft dan
in `Terminating` hangen tot je de finalizers met de hand weghaalt.

## Snel opzoeken

| Vraag | Commando |
|---|---|
| Draait alles? | `./argocd.sh status` |
| Waarom is deze app OutOfSync? | `argocd app diff <app>` · `argocd app get <app>` |
| Wat heeft Argo CD gerenderd? | `argocd app manifests <app>` |
| Waarom faalt de repo-server? | `kubectl -n argocd logs deploy/argocd-repo-server --tail=50` |
| Waarom komt er geen notificatie? | `kubectl -n argocd logs deploy/argocd-notifications-controller --tail=20` |
| Loopt een sync in een lus? | `argocd app terminate-op <app>` |
| Reageert de API niet? | `kubectl -n argocd get pods` · `curl -sk "$(./argocd.sh url)/api/version"` |

## Bronnen

- Argo CD installeren: https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/
- `argocd` CLI: https://argo-cd.readthedocs.io/en/stable/cli_installation/
- SSO/Dex: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/
- Clusterregistratie: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
