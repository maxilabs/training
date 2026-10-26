# kubeadm-config (v1beta4) — multi-document, zoals op het examen.
# Placeholders worden door cp-init.sh ingevuld.
# Uitleg (wat en waarom): SCRIPTS.md
# Drie documenten, gescheiden door '---'. Bekijk alle mogelijke velden met:
#   kubeadm config print init-defaults

# ── Document 1: InitConfiguration — instellingen voor DEZE node (cp1) bij 'kubeadm init'
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: __CP_IP__        # IP waarop de API-server luistert en dat andere nodes gebruiken
nodeRegistration:
  name: __CP_NAME__                  # naam van de node in 'kubectl get nodes'
  criSocket: unix:///run/containerd/containerd.sock   # welke container runtime (containerd)
---
# ── Document 2: ClusterConfiguration — instellingen voor het HELE cluster
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: __K8S_VERSION__   # bijv. v1.35.9; bepaalt de versies van de control-plane-images
controlPlaneEndpoint: __CP_IP__:6443 # vast adres van de API; nodig als je later meer control planes wilt
networking:
  podSubnet: __POD_CIDR__            # Pod-IP's; MOET overeenkomen met de CNI-config
  serviceSubnet: __SERVICE_CIDR__    # ClusterIP's van Services
# extraArgs: extra vlaggen voor de kube-apiserver. kubeadm zet ze in het static-Pod-manifest
# /etc/kubernetes/manifests/kube-apiserver.yaml. In v1beta4 is het een lijst name/value-paren.
apiServer:
  extraArgs:
    # Nodig voor Calico 3.33 op Kubernetes 1.34/1.35 (MutatingAdmissionPolicy is daar beta, standaard uit).
    # Vanaf 1.36 GA en standaard aan: deze twee regels mogen dan weg.
    - name: feature-gates
      value: MutatingAdmissionPolicy=true
    - name: runtime-config
      value: admissionregistration.k8s.io/v1beta1=true
---
# ── Document 3: KubeletConfiguration — instellingen voor de kubelet op ALLE nodes
# kubeadm zet dit in /var/lib/kubelet/config.yaml (ook op de workers bij 'join').
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd                # moet gelijk zijn aan containerd (SystemdCgroup = true)
