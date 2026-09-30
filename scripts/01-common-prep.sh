#!/usr/bin/env bash
# Reference only: self-managed kubeadm nodes. Do not run on OKE-managed nodes.
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

node_name=$(hostname -s)
case "$node_name" in
    cp01|cp02|cp03|worker01|worker02|worker03) ;;
    *) echo "Unexpected hostname: $node_name" >&2; exit 1 ;;
esac

ensure_hosts_entry() {
    local entry=$1
    grep -Fqx "$entry" /etc/hosts || printf '%s\n' "$entry" >> /etc/hosts
}

ensure_hosts_entry '192.168.10.11 cp01.company.local cp01'
ensure_hosts_entry '192.168.10.12 cp02.company.local cp02'
ensure_hosts_entry '192.168.10.13 cp03.company.local cp03'
ensure_hosts_entry '192.168.10.21 worker01.company.local worker01'
ensure_hosts_entry '192.168.10.22 worker02.company.local worker02'
ensure_hosts_entry '192.168.10.23 worker03.company.local worker03'
ensure_hosts_entry '192.168.10.100 kubernetes-api.company.local kubernetes-api'

dnf update -y
dnf install -y vim curl wget socat conntrack-tools chrony dnf-plugins-core
systemctl enable --now chronyd

swapoff -a
if grep -Eq '^[[:space:]]*[^#[:space:]].*[[:space:]]swap[[:space:]]' /etc/fstab; then
    sed -ri '/^[[:space:]]*[^#].*[[:space:]]swap[[:space:]]/s/^/#/' /etc/fstab
fi

setenforce 0 || true
if grep -q '^SELINUX=' /etc/selinux/config; then
    sed -ri 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
else
    printf '\nSELINUX=permissive\n' >> /etc/selinux/config
fi

cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=10250/tcp
if [[ $node_name == cp* ]]; then
    firewall-cmd --permanent --add-port=6443/tcp
    firewall-cmd --permanent --add-port=2379-2380/tcp
    firewall-cmd --permanent --add-port=10257/tcp
    firewall-cmd --permanent --add-port=10259/tcp
    firewall-cmd --permanent --add-protocol=vrrp
else
    firewall-cmd --permanent --add-port=30000-32767/tcp
    firewall-cmd --permanent --add-port=30000-32767/udp
fi
firewall-cmd --permanent --add-port=179/tcp
firewall-cmd --permanent --add-protocol=4
firewall-cmd --reload

echo "Common node preparation completed for $node_name."