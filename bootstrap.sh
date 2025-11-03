#!/usr/bin/env bash
set -euo pipefail

CONTROL_FIRST="10.0.0.10"
CONTROL_IPS=("10.0.0.10" "10.0.0.11" "10.0.0.12")
WORKER_IPS=("10.0.0.20" "10.0.0.21")
SSH_USER="ansible"
SSH_KEY="~/.ssh/id_rsa"

function remote() {
  local host=$1; shift
  ssh -o StrictHostKeyChecking=no -i ${SSH_KEY} ${SSH_USER}@${host} "${*}"
}

# 1) Prep nodes: install containerd, kubeadm, kubelet
for host in "${CONTROL_IPS[@]}" "${WORKER_IPS[@]}"; do
  echo "Preparing ${host}"
  scp -i ${SSH_KEY} prep-node.sh ${SSH_USER}@${host}:/tmp/prep-node.sh
  remote ${host} "sudo bash /tmp/prep-node.sh"
done

# 2) Init first control plane
echo "Initializing first control plane ${CONTROL_FIRST}"
remote ${CONTROL_FIRST} "sudo kubeadm init --control-plane-endpoint '${CONTROL_FIRST}:6443' --upload-certs --pod-network-cidr=10.244.0.0/16 --kubernetes-version $(kubeadm version -o short || echo 'stable')"

# fetch admin.conf and join commands
scp -i ${SSH_KEY} ${SSH_USER}@${CONTROL_FIRST}:/etc/kubernetes/admin.conf /tmp/admin.conf
echo "Saved admin.conf to /tmp/admin.conf"

JOIN_CMD=$(ssh -i ${SSH_KEY} ${SSH_USER}@${CONTROL_FIRST} "kubeadm token create --print-join-command")
CERT_KEY=$(ssh -i ${SSH_KEY} ${SSH_USER}@${CONTROL_FIRST} "kubeadm init phase upload-certs --upload-certs 2>/dev/null" || true)

echo "JOIN_CMD: $JOIN_CMD"

# 3) Join other control planes (use --control-plane + --certificate-key)
for host in "${CONTROL_IPS[@]}"; do
  if [ "$host" != "$CONTROL_FIRST" ]; then
    echo "Joining control plane ${host}"
    remote ${host} "sudo ${JOIN_CMD} --control-plane --certificate-key <CERT_KEY_PLACEHOLDER>"
  fi
done

# 4) Join workers
for host in "${WORKER_IPS[@]}"; do
  echo "Joining worker ${host}"
  remote ${host} "sudo ${JOIN_CMD}"
done

echo "Bootstrap complete. Install CNI (e.g., calico) next."


