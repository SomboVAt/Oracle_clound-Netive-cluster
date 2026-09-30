#!/usr/bin/env bash
# Reference only: self-managed kubeadm nodes. Do not run on OKE-managed nodes.
set -uo pipefail

errors=0
node_name=$(hostname -s)
case "$node_name" in
    cp01) expected_ip=192.168.10.11; control_plane=true ;;
    cp02) expected_ip=192.168.10.12; control_plane=true ;;
    cp03) expected_ip=192.168.10.13; control_plane=true ;;
    worker01) expected_ip=192.168.10.21; control_plane=false ;;
    worker02) expected_ip=192.168.10.22; control_plane=false ;;
    worker03) expected_ip=192.168.10.23; control_plane=false ;;
    *) expected_ip=; control_plane=false ;;
esac

check() {
    local description=$1
    shift
    if "$@"; then
        printf 'PASS %s\n' "$description"
    else
        printf 'FAIL %s\n' "$description"
        errors=$((errors + 1))
    fi
}

check_root() { [[ $EUID -eq 0 ]]; }
check_hostname() { [[ -n $expected_ip ]]; }
check_os() { grep -Eq '^VERSION_ID="?10([.]|"|$)' /etc/os-release; }
check_ip() { ip -o -4 addr show | awk -v address="$expected_ip" '$4 ~ ("^" address "/") {found=1} END {exit !found}'; }
check_no_swap() { [[ -z $(swapon --noheadings --show) ]]; }
check_service() { systemctl is-active --quiet "$1"; }
check_module() { lsmod | awk -v module="$1" '$1 == module {found=1} END {exit !found}'; }
check_sysctl() { [[ $(sysctl -n "$1" 2>/dev/null) == 1 ]]; }
check_package() { rpm -q "$1" >/dev/null 2>&1; }

printf 'Preflight for %s\n' "$(hostname -f 2>/dev/null || hostname)"
check "running as root" check_root
check "Oracle Linux 10" check_os
check "hostname is a configured cluster node" check_hostname
if [[ -n $expected_ip ]]; then
    check "expected node address $expected_ip is configured" check_ip
fi
check "swap is disabled" check_no_swap
check "chronyd is active" check_service chronyd
check "firewalld is active" check_service firewalld
check "overlay module is loaded" check_module overlay
check "br_netfilter module is loaded" check_module br_netfilter
check "IPv4 forwarding is enabled" check_sysctl net.ipv4.ip_forward
check "bridge iptables is enabled" check_sysctl net.bridge.bridge-nf-call-iptables
check "containerd is installed" check_package containerd.io
check "containerd is active" check_service containerd
check "kubelet is installed" check_package kubelet
check "kubeadm is installed" check_package kubeadm
check "kubectl is installed" check_package kubectl

if [[ $control_plane == true ]]; then
    check "HAProxy is installed" check_package haproxy
    check "Keepalived is installed" check_package keepalived
    check "HAProxy configuration is valid" haproxy -c -f /etc/haproxy/haproxy.cfg
    check "HAProxy is active" check_service haproxy
    check "Keepalived is active" check_service keepalived
fi

if (( errors > 0 )); then
    printf '\nPreflight failed with %d check(s).\n' "$errors" >&2
    exit 1
fi
printf '\nAll preflight checks passed.\n'