#!/usr/bin/env bash
# Snapshots van alle lab-VM's tegelijk.
# Uitleg (wat en waarom): SCRIPTS.md
# Gebruik: ./snapshot.sh save <naam> | revert <naam> | list | delete <naam>
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env

# $1 = actie (standaard 'list'), $2 = naam van de snapshot.
ACTION="${1:-list}"; SNAP="${2:-}"
# need: stopt met een melding als je de naam vergeten bent.
need() { [ -n "$SNAP" ] || die "naam ontbreekt: ./snapshot.sh $ACTION <naam>"; }

case "$ACTION" in
  # save: per VM een interne libvirt-snapshot (disk + RAM, want de VM draait).
  # Alle drie de nodes krijgen dezelfde naam, zodat je het cluster als geheel terugzet.
  save)   need
          for n in $(node_names); do
            # cloud-init-ISO (cdrom, geen qcow2) blokkeert interne snapshots: eerst uitwerpen
            for t in $(virsh domblklist "$n" --details | awk '$2=="cdrom"{print $3}'); do
              virsh change-media "$n" "$t" --eject --live --config >/dev/null 2>&1 || true
            done
            # --atomic: de snapshot lukt helemaal of helemaal niet (geen halve snapshot).
            log "save $n@$SNAP"; virsh snapshot-create-as "$n" "$SNAP" --atomic >/dev/null
          done ;;
  # revert: alle VM's terug naar die snapshot; --running = daarna meteen weer aan.
  # Na 20 s laten we de nodes zien; even NotReady direct na een revert is normaal.
  revert) need; for n in $(node_names); do log "revert $n@$SNAP"; virsh snapshot-revert "$n" "$SNAP" --running; done
          log "Even wachten tot de kubelets weer Ready melden..."; sleep 20
          vm_ssh "$CP_NODE" 'kubectl get nodes' || true ;;
  # delete: snapshot weggooien ('|| true': bestaat hij op een node niet, dan geen fout).
  delete) need; for n in $(node_names); do virsh snapshot-delete "$n" "$SNAP" || true; done ;;
  # list: per node de namen van alle snapshots.
  list)   for n in $(node_names); do echo "## $n"; virsh snapshot-list "$n" --name; done ;;
  *)      die "onbekende actie: $ACTION (save|revert|list|delete)" ;;
esac
