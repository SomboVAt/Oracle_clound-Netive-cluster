#!/usr/bin/env bash
# Reference only: local Oracle Linux 7 cluster deployment without OCI.
# This script prepares a self-managed kubeadm cluster modeled after the
# repo's OCNE / kubeadm reference design. It is not an Oracle OCI/OKE deployment.

set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

: "${CONTROL_PLANE_ENDPOINT:=kubernetes-api.company.local:6443}"
: "${API_VIP:=192.168.10.100}"
: "${NODE_IP:=$(hostname -I | awk '{print $1}')}"
: "${POD_CIDR:=10.244.0.0/16}"
: "${KUBERNETES_MINOR_VERSION:=1.37}"
: "${KUBEADM_REPO:=/etc/yum.repos.d/kubernetes.repo}"

node_name=$(hostname -s)
case "$node_name" in
    cp01|cp02|cp03|worker01|worker02|worker03) ;;
    *)
        echo "Unexpected hostname: $node_name" >&2
        echo "Expected one of cp01, cp02, cp03, worker01, worker02, worker03." >&2
        exit 1
        ;;
esac

printf '==> Oracle Linux 7 local OCNE-style deployment\n'
printf '    HOST=%s\n    NODE_IP=%s\n    CONTROL_PLANE_ENDPOINT=%s\n    API_VIP=%s\n' "$node_name" "$NODE_IP" "$CONTROL_PLANE_ENDPOINT" "$API_VIP"

check_os() {
    if ! grep -Eq '^VERSION_ID="?7([.]|"|$)' /etc/os-release; then
        echo "This script expects Oracle Linux 7." >&2
        exit 1
    fi
}

install_base_packages() {
    yum update -y
    yum install -y vim curl wget socat conntrack-tools chrony yum-utils
    systemctl enable --now chronyd
}

prepare_kernel_and_network() {
    swapoff -a || true
    sed -i '/swap/s/^/#/' /etc/fstab || true

    setenforce 0 || true
    if grep -Eq '^SELINUX=' /etc/selinux/config; then
        sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
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
}

install_containerd() {
    yum install -y yum-utils

    if ! yum repolist all | awk '$1 == "ol7_addons" { found = 1 } END { exit !found }'; then
        echo "Oracle Linux repository 'ol7_addons' is missing; configuring Oracle's public Oracle Linux 7 Addons repository."
        cat > /etc/yum.repos.d/oracle-ol7-addons.repo <<'EOF'
[ol7_addons]
name=Oracle Linux 7 Addons ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL7/addons/$basearch/
gpgkey=https://yum.oracle.com/RPM-GPG-KEY-oracle-ol7
gpgcheck=1
enabled=1
EOF
    fi
    yum-config-manager --enable ol7_addons
    yum makecache fast --disablerepo='*' --enablerepo=ol7_addons
    yum install -y container-selinux

    if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    yum install -y containerd.io
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || {
        echo "Failed to enable SystemdCgroup in containerd config." >&2
        exit 1
    }
    systemctl enable --now containerd
}

install_kubernetes_repo() {
    cat > "$KUBEADM_REPO" <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

    yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    systemctl enable --now kubelet
}

configure_firewall() {
    systemctl enable --now firewalld
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --add-port=10250/tcp
    if [[ $node_name == cp* ]]; then
        firewall-cmd --permanent --add-port=6443/tcp
        firewall-cmd --permanent --add-port=2379-2380/tcp
        firewall-cmd --permanent --add-port=10257/tcp
        firewall-cmd --permanent --add-port=10259/tcp
    else
        firewall-cmd --permanent --add-port=30000-32767/tcp
        firewall-cmd --permanent --add-port=30000-32767/udp
    fi
    firewall-cmd --permanent --add-port=179/tcp
    firewall-cmd --reload
}

prepare_hosts() {
    local entries=(
        "192.168.10.11 cp01.company.local cp01"
        "192.168.10.12 cp02.company.local cp02"
        "192.168.10.13 cp03.company.local cp03"
        "192.168.10.21 worker01.company.local worker01"
        "192.168.10.22 worker02.company.local worker02"
        "192.168.10.23 worker03.company.local worker03"
        "192.168.10.100 kubernetes-api.company.local kubernetes-api"
    )

    for entry in "${entries[@]}"; do
        grep -Fqx "$entry" /etc/hosts || printf '%s\n' "$entry" >> /etc/hosts
    done
}

check_os
prepare_hosts
install_base_packages
prepare_kernel_and_network
install_containerd
install_kubernetes_repo
configure_firewall

if [[ $node_name == cp01 ]]; then
    echo "==> cp01: initializing kubeadm control plane"
    kubernetes_version=$(kubeadm version -o short)
    echo "==> Pulling Kubernetes control-plane images from registry.k8s.io"
    kubeadm config images pull \
      --kubernetes-version="${kubernetes_version}" \
      --cri-socket=unix:///run/containerd/containerd.sock

    kubeadm init \
      --kubernetes-version="${kubernetes_version}" \
      --control-plane-endpoint="${CONTROL_PLANE_ENDPOINT}" \
      --apiserver-advertise-address=192.168.10.11 \
      --cri-socket=unix:///run/containerd/containerd.sock \
      --upload-certs \
      --pod-network-cidr="${POD_CIDR}"

    mkdir -p "$HOME/.kube"
    cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    chown "$(id -u):$(id -g)" "$HOME/.kube/config"

    echo "==> cp01: install Calico"
    curl -fsSLo /tmp/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
    sed -i '/# - name: CALICO_IPV4POOL_CIDR/{s/# - name:/- name:/; n; s/#   value:/  value:/; s#192\.168\.0\.0/16#10.244.0.0/16#;}' /tmp/calico.yaml
    kubectl apply -f /tmp/calico.yaml

    echo "==> Save this join command for cp02/cp03 and workers:"
    kubeadm token create --print-join-command
    echo "==> If you need a control-plane join command with the certificate key, run:"
    echo "    kubeadm init phase upload-certs --upload-certs"
else
    echo "==> ${node_name}: waiting for control-plane bootstrap. Run a join command from cp01."
fi

cat <<'EOF'

This script only prepares the hosts and executes the kubeadm init/join flow.
For a production lab, review the generated join commands, verify the VIP and hostnames,
then complete the remaining cluster validation steps from the README before using the cluster.
EOF
