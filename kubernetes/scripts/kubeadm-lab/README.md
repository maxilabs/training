# kubeadm-lab — CKA-studie

Studiemap voor de CKA (Kubernetes v1.35), met een oefencluster van 3 VM's op aristotle.

## De documenten

| Document | Rol | Begin hier als… |
|---|---|---|
| [CONCEPTS](CONCEPTS.md) | **de kern**: elk begrip als los object, met een vaste opbouw | je wilt begrijpen wat iets is en waarom |
| [STUDIEPLAN](STUDIEPLAN.md) | volgorde, blokken en labs; elk lab linkt naar zijn begrippen | je wilt weten wat je nu gaat leren en oefenen |
| [INIT](INIT.md) | de lab-omgeving opzetten en resetten (VM's, cluster, CNI, add-ons) | je je lab wilt bouwen of herstellen |
| [SCRIPTS](SCRIPTS.md) | wat de scripts onder water doen, met het handmatige equivalent | je wilt weten wat een script precies doet |

Voor blok 7 (GitOps) is er een eigen labmap: [gitops-lab](../../gitops-lab/README.md) met
[LABS](../../gitops-lab/LABS.md) (G-01 t/m G-18), [CONCEPTS](../../gitops-lab/CONCEPTS.md) en
[SCRIPTS](../../gitops-lab/SCRIPTS.md). Daar staat Argo CD als containers in ditzelfde cluster, met de manifests
in git naast deze vault.

Daarnaast voor blok 8: `iac/` met per scenario een eigen handleiding, [lab-libvirt](iac/lab-libvirt/README.md) · [aks-azure](iac/aks-azure/README.md) · [aks-azurelocal](iac/aks-azurelocal/README.md), en `.github/workflows/` met de pipelines.

## De studiemethode

1. **Begrip eerst.** Lees in CONCEPTS het object dat je gaat oefenen: wat is het, waarom bestaat het, hoe werkt het.
2. **Kleine praktische stap.** Doe één lab of één stap uit het STUDIEPLAN (of INIT), op je eigen cluster.
3. **Bronnen op het moment zelf.** Lees de officiële documentatie die bij dat begrip staat, terwijl je de stap doet.
4. **Zie het zelf.** Controleer met de commando's uit CONCEPTS of wat je ziet klopt met wat je verwacht.
5. **Werk het begrip bij.** Is een begrip nog een stub (📝), dan wordt het uitgewerkt (✅) zodra je bij dat blok bent.

Elk lab in het STUDIEPLAN en elke stap in INIT heeft een regel **🔗 Begrippen** met klikbare links naar CONCEPTS.

## Links in VS Code en Obsidian

Alle links hebben de vorm `[tekst](CONCEPTS.md#id)`, en de kop van elk begrip is precies dat id (kleine letters
met streepjes). Daardoor werken ze in de VS Code-preview én in Obsidian.

In Obsidian: open **deze map** als vault (of een map erboven, zolang de bestandsnamen uniek zijn), en zet bij
*Instellingen → Bestanden en links* "Gebruik [[Wikilinks]]" uit als je zelf links toevoegt. Dan blijven nieuwe
links in hetzelfde formaat.
