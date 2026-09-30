#!/usr/bin/env bash
# Reference only: self-managed kubeadm nodes. Do not run on OKE-managed nodes.
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io
install -d -m 0755 /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -ri 's/^([[:space:]]*)SystemdCgroup = false$/\1SystemdCgroup = true/' /etc/containerd/config.toml
grep -q '^[[:space:]]*SystemdCgroup = true$' /etc/containerd/config.toml || {
    echo "Could not enable SystemdCgroup in containerd configuration." >&2
    exit 1
}
systemctl enable --now containerd
systemctl restart containerd

echo "containerd is installed and using systemd cgroups."