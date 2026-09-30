#!/usr/bin/env bash
# Reference only: self-managed kubeadm nodes. Do not run on OKE-managed nodes.
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

kubernetes_minor_version=${KUBERNETES_MINOR_VERSION:-1.36}
if [[ ! $kubernetes_minor_version =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "KUBERNETES_MINOR_VERSION must look like 1.36." >&2
    exit 1
fi

cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kubernetes_minor_version}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kubernetes_minor_version}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo "Kubernetes packages installed from the v${kubernetes_minor_version} channel."