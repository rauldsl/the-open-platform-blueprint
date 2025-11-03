#cloud-config
runcmd:
  - |
    set -e
    # install containerd & kubeadm like control
    apt-get update
    apt-get install -y containerd kubelet kubeadm
    sysctl net.bridge.bridge-nf-call-iptables=1
    # join -- in real flow we need a join token and control-plane endpoint
    # This placeholder expects you to replace with actual join command with token:
    # kubeadm join <control-plane-lb>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
