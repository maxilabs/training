# gitops-lab — alle GitOps-concepten met Argo CD

**Wat dit is.** Een lab waarmee je GitOps van begin tot eind leert op je eigen kubeadm-cluster: Argo CD
draait als containers (Pods) in het cluster, leest de gewenste toestand uit **deze repo**, en houdt het
cluster daar continu gelijk aan. Je oefent op echte objecten: van je eerste `Application` tot
`ApplicationSet`, `AppProject`, SSO, notificaties en disaster recovery.

**Waarom GitOps.** Git wordt de enige bron van waarheid: elke wijziging is een commit (review,
geschiedenis, terugdraaien) en afwijkingen in het cluster (*drift*) worden zichtbaar of automatisch
teruggezet. Zie [CONCEPTS](CONCEPTS.md#gitops) voor het waarom, en [CONCEPTS](CONCEPTS.md#push-vs-pull)
voor het verschil met een CI/CD-pipeline die één keer `kubectl apply` doet.

## De documenten

| Document | Rol | Begin hier als… |
|---|---|---|
| [LABS](LABS.md) | de labs G-01 t/m G-18, elk met stappen, verificatie en links naar de begrippen | je wilt oefenen |
| [CONCEPTS](CONCEPTS.md) | elk GitOps-/Argo CD-begrip als los object, met een vaste opbouw | je wilt begrijpen wat iets is en waarom |
| [SCRIPTS](SCRIPTS.md) | wat `../scripts/kubeadm-lab/argocd.sh` onder water doet, met het handmatige equivalent | je wilt weten wat een commando precies doet |

Deze map hoort bij de vault: [README van de vault](../scripts/kubeadm-lab/README.md) ·
[STUDIEPLAN blok 7](../scripts/kubeadm-lab/STUDIEPLAN.md) · [CONCEPTS van de vault](../scripts/kubeadm-lab/CONCEPTS.md).

## Snelstart

Alles draait vanaf **aristotle** (de host met de VM's); de scripts voeren het werk uit op **cp1**.

```bash
cd ~/kubernetes/scripts/kubeadm-lab

./argocd.sh install      # Argo CD v3.5.6 in het cluster + NodePort + argocd-CLI op cp1
./argocd.sh login        # argocd-CLI inloggen (context 'lab')
./argocd.sh bootstrap    # de root-Application toepassen: Argo CD neemt het over

./argocd.sh status       # pods, applications, projects
./argocd.sh url          # https://192.168.122.11:30443  (admin / zie ./argocd.sh password)
```

Daarna open je de UI in je browser en begin je bij [LABS → G-02](LABS.md#g-02).

Opruimen: `./argocd.sh reset` (lab-apps weg, Argo CD blijft) of `./argocd.sh uninstall` (alles weg).

## Wat er in deze map staat

```
gitops-lab/
├── bootstrap/root-app.yaml        de enige Application die je met de hand aanmaakt (app-of-apps)
├── clusters/lab/
│   ├── apps/                      Applications: dit is de gewenste toestand van dít cluster
│   │   ├── platform.yaml          Argo CD's eigen configuratie (project, RBAC, notificaties)
│   │   ├── echo-receiver.yaml     ontvanger voor notificaties
│   │   ├── web-lab.yaml           dezelfde app als web-prod, andere overlay
│   │   ├── web-prod.yaml
│   │   ├── helm-demo.yaml         Helm-bron
│   │   ├── waves.yaml             sync waves + hooks
│   │   └── guests-appset.yaml     ApplicationSet (drie omgevingen uit git)
│   └── optional/                  labs die je zelf aanzet: waves-fail, health-crd, multi-cluster
├── platform/                      AppProject, argocd-rbac-cm, argocd-notifications-cm
└── workloads/                     de workload-manifests zelf (Kustomize, Helm-chart, hooks, CRD)
```

De scheiding is bewust: **`clusters/` zegt wát er waar moet staan, `workloads/` bevat hoe het eruitziet.**
Zo kun je dezelfde workload in twee clusters of omgevingen gebruiken.

## Twee dingen die je moet weten voordat je begint

1. **De repo is publiek.** Argo CD leest `https://github.com/maxilabs/training.git` zonder
   credentials. Oefen je met een private repo, dan heb je een deploy key of token nodig
   ([CONCEPTS](CONCEPTS.md#repo-credentials), lab G-11). Zet **nooit** echte secrets in git
   ([CONCEPTS](CONCEPTS.md#secrets-in-git)).
2. **GitHub kan je cluster niet bereiken.** De VM's hangen in het libvirt-netwerk (192.168.122.0/24),
   dus een GitHub-webhook komt nooit aan. Argo CD pollt de repo daarom elke 3 minuten. Voor direct
   resultaat gebruik je `argocd app get <app> --refresh` of `argocd app sync <app>`
   ([CONCEPTS](CONCEPTS.md#webhooks-vs-polling)).

## Werkafspraken (zo blijft het lab heel)

- Alles wat Argo CD beheert wijzig je **in git**, niet met `kubectl edit`. Dat is niet flauw bedoeld:
  de volgende reconcile zet je handmatige wijziging terug. Dat ís de les (lab G-03).
- De labs die je zelf aanzet (`clusters/lab/optional/`) staan bewust buiten `clusters/lab/apps/`,
  zodat de root-app groen blijft als zo'n lab met opzet faalt.
- Na een lab: `./argocd.sh reset` en je begint weer schoon. Argo CD zelf blijft staan.
- Werk je vanaf een snapshot? Maak eerst een snapshot van de huidige staat (`./snapshot.sh save calico-ready`), dan kun je altijd terug.
