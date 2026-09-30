#!/usr/bin/env bash
# Reference only: self-managed kubeadm nodes. Do not run on OKE-managed nodes.
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
fi

node_name=$(hostname -s)
case "$node_name" in
    cp01) node_ip=192.168.10.11; priority=100; state=MASTER; peers=$'192.168.10.12\n192.168.10.13' ;;
    cp02) node_ip=192.168.10.12; priority=90; state=BACKUP; peers=$'192.168.10.11\n192.168.10.13' ;;
    cp03) node_ip=192.168.10.13; priority=80; state=BACKUP; peers=$'192.168.10.11\n192.168.10.12' ;;
    *) echo "Run this script only on cp01, cp02, or cp03 (found $node_name)." >&2; exit 1 ;;
esac

keepalived_auth_pass=${KEEPALIVED_AUTH_PASS:-}
haproxy_stats_password=${HAPROXY_STATS_PASSWORD:-}
if [[ ! $keepalived_auth_pass =~ ^[A-Za-z0-9]{1,8}$ ]]; then
    echo "Set KEEPALIVED_AUTH_PASS to a shared 1-8 character alphanumeric value." >&2
    exit 1
fi
if [[ ! $haproxy_stats_password =~ ^[A-Za-z0-9._-]{12,128}$ ]]; then
    echo "Set HAPROXY_STATS_PASSWORD to a 12-128 character value using letters, digits, ., _, or -." >&2
    exit 1
fi

cluster_interface=${CLUSTER_INTERFACE:-$(ip -o -4 route get 192.168.10.100 | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')}
if [[ -z $cluster_interface ]]; then
    echo "Could not determine the cluster interface; set CLUSTER_INTERFACE explicitly." >&2
    exit 1
fi

dnf install -y haproxy keepalived
cat > /etc/sysctl.d/99-vip.conf <<'EOF'
net.ipv4.ip_nonlocal_bind = 1
EOF
sysctl --system

cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log         /dev/log local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

defaults
    mode                    tcp
    log                     global
    option                  tcplog
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout check           5s
    timeout client          86400s
    timeout server          86400s
    timeout http-request    10s
    maxconn                 3000

frontend k8s-api
    bind 192.168.10.100:6443
    mode tcp
    option tcplog
    default_backend k8s-api

backend k8s-api
    mode tcp
    balance roundrobin
    option tcp-check
    server cp01 192.168.10.11:6443 check fall 3 rise 2
    server cp02 192.168.10.12:6443 check fall 3 rise 2
    server cp03 192.168.10.13:6443 check fall 3 rise 2

listen haproxy-stats
    mode http
    bind *:8404
    stats enable
    stats uri /
    stats refresh 5s
    stats auth admin:${haproxy_stats_password}
EOF

cat > /etc/keepalived/keepalived.conf <<EOF
vrrp_script check_haproxy {
    script "pidof haproxy"
    interval 2
    weight -30
    fall 2
    rise 2
}

vrrp_instance VI_1 {
    state ${state}
    interface ${cluster_interface}
    virtual_router_id 51
    priority ${priority}
    advert_int 1
    unicast_src_ip ${node_ip}
    unicast_peer {
$(while IFS= read -r peer; do printf '        %s\n' "$peer"; done <<< "$peers")
    }
    authentication {
        auth_type PASS
        auth_pass ${keepalived_auth_pass}
    }
    virtual_ipaddress {
        192.168.10.100/24
    }
    track_script {
        check_haproxy
    }
}
EOF

chmod 0600 /etc/keepalived/keepalived.conf
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable --now haproxy keepalived

echo "HAProxy and Keepalived configured on $node_name ($node_ip)."