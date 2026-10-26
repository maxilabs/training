#!/usr/bin/env bash
# Start het lab weer na een reboot van aristotle: libvirt-netwerk + alle VM's.
# Uitleg (wat en waarom): SCRIPTS.md
# Gebruik: ./start-vms.sh
#
# Waarom nodig? libvirt start na een reboot alleen wat op 'autostart' staat. Staan het
# netwerk en de VM's daar niet op, dan is je cluster "weg" (No route to host), terwijl
# alles nog gewoon op schijf staat. Dit script start ze en zet autostart aan, zodat het
# na de volgende reboot vanzelf gaat. Veilig om vaker te draaien.
set -euo pipefail            # stop bij de eerste fout (zie create-vms.sh)
cd "$(dirname "$0")"; source ./lab.env   # lab.env zet ook LIBVIRT_DEFAULT_URI=qemu:///system

# 1. Het netwerk (192.168.122.0/24). net-start faalt als het al draait: dat is prima.
if ! virsh net-info "$LIBVIRT_NET" | grep -q 'Active:.*yes'; then
  log "netwerk '$LIBVIRT_NET' starten"
  virsh net-start "$LIBVIRT_NET" >/dev/null
fi
# autostart = libvirt start het netwerk voortaan zelf bij het opstarten van de host.
virsh net-autostart "$LIBVIRT_NET" >/dev/null

# 2. De VM's. 'virsh domstate' geeft running / shut off / paused.
for n in $(node_names); do
  virsh dominfo "$n" >/dev/null 2>&1 || die "VM $n bestaat niet: bouw het lab met ./bootstrap.sh"
  case "$(virsh domstate "$n")" in
    running) log "$n draait al" ;;
    paused)  log "$n hervatten"; virsh resume "$n" >/dev/null ;;
    *)       log "$n starten";   virsh start "$n" >/dev/null ;;
  esac
  virsh autostart "$n" >/dev/null   # ook deze VM voortaan automatisch starten
done

# 3. Wachten tot de API-server antwoordt. Na het booten start de kubelet de control plane
#    (static Pods in /etc/kubernetes/manifests); dat duurt meestal 30-60 seconden.
log "wachten op de API-server op $CP_NODE (max. 3 minuten)"
for i in $(seq 1 36); do
  if vm_ssh "$CP_NODE" 'kubectl get --raw=/readyz' >/dev/null 2>&1; then break; fi
  [ "$i" -eq 36 ] && die "API-server antwoordt niet. Kijk op $CP_NODE: sudo crictl ps -a"
  sleep 5
done

# 4. Status tonen. NotReady + coredns Pending is normaal zolang er geen CNI is.
log "status"
vm_ssh "$CP_NODE" 'kubectl get nodes -o wide; echo; kubectl -n kube-system get pods'
