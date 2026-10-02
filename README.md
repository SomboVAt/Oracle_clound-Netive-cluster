# Oracle Cloud Core-Banking Kubernetes Deployment Guide

This guide recommends Oracle Kubernetes Engine (OKE) for the application tier of a new cloud banking deployment. The existing kubeadm instructions are retained as a separate, self-managed reference; they do not create an OKE or OCNE cluster and are not a production core-banking design by themselves.

## Recommended OCI Installation: OKE

Use OKE when you want Oracle to manage the Kubernetes control plane. Treat the node size below as a load-test starting point, not a final production capacity decision. Validate the design against your bank's security, regulatory, vendor-certification, latency, and recovery requirements.

1. **Confirm requirements.** Choose the OCI region and confirm data residency, peak transactions per second, concurrency, latency target, recovery time objective (RTO), recovery point objective (RPO), and supported application/database versions. Check current OKE Kubernetes versions for the target region before creating the cluster.
2. **Prepare tenancy and capacity.** Create a dedicated compartment, grant least-privilege IAM access, check Compute/OKE service limits and regional capacity, and estimate costs. Use a capacity reservation if the workload requires guaranteed capacity.
3. **Build the network.** Create a VCN with private node subnets and a private Kubernetes API endpoint. Define non-overlapping VCN, pod, service, and on-premises CIDRs. Use NSGs to allow only required application, cluster, database, and administration traffic. Provide administrator access through VPN/FastConnect or OCI Bastion; do not assign public IPs to nodes.
4. **Create the OKE cluster.** Use the Terraform configuration below to create an Enhanced cluster with a private API endpoint. Select a Kubernetes version currently offered for the region; as of 2026-09-30, Oracle's supported-version page lists 1.36.1 as the newest supported version. Recheck regional support at deployment time.
5. **Create the worker node pool.** Terraform starts with three private x86 `VM.Standard.E6.Flex` nodes at 8 OCPUs and 64 GB RAM each, using an OKE-supported Oracle Linux image. Spread nodes across availability domains where available, or fault domains otherwise. Benchmark peak load and a node-loss scenario before approving production size; avoid Arm unless every application and vendor dependency is certified for it.
6. **Provision the data tier separately.** Use a supported managed database service for the core ledger/database tier where it meets requirements. Keep durable banking data off Kubernetes node boot disks and ephemeral containers. Configure database HA, encryption, backup, and replication according to the selected service and the approved RPO/RTO.
7. **Apply workload security and availability controls.** Store secrets in OCI Vault, use workload identity and least-privilege IAM, encrypt volumes with managed keys, and enable audit, logging, monitoring, and alerting. Deploy multiple application replicas with resource requests/limits, readiness/liveness probes, topology spreading, disruption budgets, and tested autoscaling.
8. **Prove recovery before production.** Test peak throughput, latency, node and availability-domain failure, database restore/failover, and regional DR. Document runbooks and obtain security, compliance, and application-vendor sign-off.

OKE manages the control plane, so you do not create control-plane VMs or configure Keepalived for its API endpoint. For Oracle Cloud Native Environment (OCNE), follow the current OCNE Release 2 `ocne`/OCK workflow instead; do not mix it with the kubeadm scripts below.

### Terraform Configuration

The [`terraform/`](terraform/) directory uses Oracle's maintained OKE Terraform module pinned to `v5.5.1`. It creates an OKE Enhanced cluster and managed node pool in existing private subnets; it does not create your VCN. This keeps production CIDRs, routes, and network controls under your organization's approval. Review the module documentation and each Terraform plan before applying.

Prerequisites: Terraform 1.5 or newer, an OCI CLI profile configured on the deployment workstation, IAM permissions for the target compartment, an approved VCN with private `cp`, `workers`, and `int_lb` subnets, valid regional availability-domain numbers, and approved administrator CIDRs. The profile and `terraform.tfvars` contain environment-specific values; never commit credentials, state, plans, or real `.tfvars` files.

If you do not have OCI access for testing, set `deploy_oke = false` in `terraform.tfvars` (or pass `-var='deploy_oke=false'`) to skip the OCI module while still validating Terraform syntax and variable handling.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real OCIDs, region, subnets, CIDRs, and AD numbers.
# For a local-only syntax check without OCI credentials, set deploy_oke = false.
terraform init
terraform fmt -check
terraform validate
terraform plan -out=oke.tfplan
terraform show oke.tfplan
# Apply only after review and approval:
terraform apply oke.tfplan
```

The sample profile disables public control-plane access, public worker IPs, public load balancers, bastion/operator VMs, and broad worker/pod internet egress. Ensure the existing VCN provides required private routing to OCI services and approved registries. Configure an organization-approved remote, encrypted Terraform state backend before team or production use; the default local state is only suitable for a controlled test. Do not run `terraform apply` until all placeholders and security controls have been reviewed.

| Terraform file | Purpose |
|---|---|
| [`terraform/main.tf`](terraform/main.tf) | Pins and configures Oracle's OKE module, private cluster, and managed worker pool. |
| [`terraform/providers.tf`](terraform/providers.tf) | Uses the local OCI CLI profile for the workload and home regions. |
| [`terraform/versions.tf`](terraform/versions.tf) | Sets Terraform compatibility and the official Oracle OCI provider source/version range. |
| [`terraform/variables.tf`](terraform/variables.tf) | Defines region, network, access, image, version, and worker sizing inputs. |
| [`terraform/outputs.tf`](terraform/outputs.tf) | Exposes cluster and worker-pool identifiers/endpoints only. |
| [`terraform/terraform.tfvars.example`](terraform/terraform.tfvars.example) | Placeholder values to copy and customize locally; not deployable as-is. |
| [`terraform/.terraform.lock.hcl`](terraform/.terraform.lock.hcl) | Generated dependency lockfile from `terraform init`; commit it to pin provider selections. |
| [`.gitignore`](.gitignore) | Excludes Terraform state, plans, local variables, and downloaded plugins. |

## Self-Managed kubeadm Reference

The following sections describe a separate six-VM kubeadm cluster (three control planes and three workers). Use it only when you have chosen to operate Kubernetes yourself and have validated the OS, runtime, CNI, networking, support, and security model. In OCI, replace the floating Keepalived VIP with an OCI-supported load-balancer design. This reference is not a substitute for OKE or OCNE.

### Repository Scripts

The scripts automate host preparation and package/service installation for the self-managed kubeadm reference. They do not create OCI VMs, VCNs, load balancers, an OKE cluster, or a Kubernetes cluster. Set each host's name before running them. Run all scripts as `root` on the indicated hosts.

| File | Run on | Purpose |
|---|---|---|
| [`scripts/01-common-prep.sh`](scripts/01-common-prep.sh) | All six nodes | Adds cluster host records, updates the OS, configures swap/SELinux/kernel networking, and applies firewalld rules. |
| [`scripts/02-containerd.sh`](scripts/02-containerd.sh) | All six nodes | Installs containerd from the Docker CentOS repository and enables systemd cgroups. Validate that repository's Oracle Linux 10 support first. |
| [`scripts/03-k8s-packages.sh`](scripts/03-k8s-packages.sh) | All six nodes | Installs kubelet, kubeadm, and kubectl from the Kubernetes v1.36 repository. Set `KUBERNETES_MINOR_VERSION` only if intentionally selecting another minor. |
| [`scripts/04-haproxy-keepalived.sh`](scripts/04-haproxy-keepalived.sh) | cp01, cp02, cp03 | Generates HAProxy/Keepalived configuration and enables both services. Requires passwords and the cluster interface. |
| [`scripts/preflight-check.sh`](scripts/preflight-check.sh) | All six nodes | Checks host prerequisites and installed services; it does not validate cluster health, firewall source restrictions, or Calico operation. |

#### Script Order

1. Set the hostname on each node to the matching name in the environment table. Confirm the node IP, DNS/network access, and that the VIP is reserved. The common-preparation script adds the `/etc/hosts` records.
2. Run the preparation script on every node:

	```bash
	./scripts/01-common-prep.sh
	```

3. On every node, install the runtime and Kubernetes packages in order:

	```bash
	./scripts/02-containerd.sh
	./scripts/03-k8s-packages.sh
	```

4. On each control-plane node, set the same Keepalived password and explicitly set that host's cluster-facing interface. Use a strong HAProxy statistics password; do not commit real passwords or put them in this README. The Keepalived password is limited to eight alphanumeric characters by the protocol.

	```bash
	read -rsp 'Keepalived auth password: ' KEEPALIVED_AUTH_PASS; printf '\n'
	read -rsp 'HAProxy statistics password: ' HAPROXY_STATS_PASSWORD; printf '\n'
	export KEEPALIVED_AUTH_PASS HAPROXY_STATS_PASSWORD
	export CLUSTER_INTERFACE='<this-hosts-cluster-interface>'
	./scripts/04-haproxy-keepalived.sh
	unset KEEPALIVED_AUTH_PASS HAPROXY_STATS_PASSWORD CLUSTER_INTERFACE
	```

	Set `CLUSTER_INTERFACE` explicitly on every control plane; automatic route detection can select `lo` on the node that currently owns the VIP. In OCI, use an OCI-supported load balancer instead of relying on this script's Keepalived VIP configuration.
5. Run the preflight check on every node. Control-plane checks expect HAProxy and Keepalived to have been installed and started first:

	```bash
	./scripts/preflight-check.sh
	```

6. Continue with the manual kubeadm initialization, join, and Calico steps below. The scripts do not perform those steps.

The preparation script makes SELinux permissive and enables firewalld. Treat both as security decisions requiring review. Tigera warns that firewalld can interfere with Calico; validate a supported host-firewall policy and the required Calico traffic in a test environment before production. Restrict node, etcd, kubelet, and HA traffic to trusted source networks in both host firewalls and OCI NSGs.

### Environment

| Hostname | Address | Role |
|---|---|---|
| `cp01.company.local` | `192.168.10.11` | Control plane, HAProxy, Keepalived (preferred master) |
| `cp02.company.local` | `192.168.10.12` | Control plane, HAProxy, Keepalived (backup) |
| `cp03.company.local` | `192.168.10.13` | Control plane, HAProxy, Keepalived (backup) |
| `worker01.company.local` | `192.168.10.21` | Worker |
| `worker02.company.local` | `192.168.10.22` | Worker |
| `worker03.company.local` | `192.168.10.23` | Worker |
| `kubernetes-api.company.local` | `192.168.10.100` | API virtual IP (VIP) |

Commands below run as `root` on Oracle Linux 10 unless stated otherwise. Replace example secrets and verify your network interface, DNS, repository access, and selected Kubernetes/Calico version compatibility before deployment. Keep the control-plane and worker clocks synchronized. Ensure the VIP is reserved and unused by another host.

The Kubernetes package channel below targets v1.36. Calico v3.32 is tested with Kubernetes 1.34 through 1.36. Keep all Kubernetes packages on the same minor release and check the upstream and Oracle support policies before production use. Do not expose HAProxy statistics or use example credentials on an untrusted network.

### 1. Prepare All Nodes

Set each node's hostname to its matching FQDN from the table above. For example, on cp01:

```bash
hostnamectl set-hostname cp01.company.local
```

Add these records to `/etc/hosts` on all six nodes, preserving existing localhost entries. Add the block only once:

```text
192.168.10.11 cp01.company.local cp01
192.168.10.12 cp02.company.local cp02
192.168.10.13 cp03.company.local cp03
192.168.10.21 worker01.company.local worker01
192.168.10.22 worker02.company.local worker02
192.168.10.23 worker03.company.local worker03
192.168.10.100 kubernetes-api.company.local kubernetes-api
```

Update the system, install prerequisites, and enable time synchronization:

```bash
dnf update -y
dnf install -y vim curl wget socat conntrack-tools chrony dnf-plugins-core
systemctl enable --now chronyd
```

Disable swap now and at boot. Confirm the `sed` command comments the swap entry in your `/etc/fstab`:

```bash
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab
```

Set SELinux permissive for this Kubernetes setup:

```bash
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

Load the required kernel modules and networking settings:

```bash
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
```

### 2. Install containerd on All Nodes

The Docker CentOS repository is used here to obtain `containerd.io`. Confirm the repository supports your Oracle Linux 10 environment before relying on it in production.

```bash
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep 'SystemdCgroup = true' /etc/containerd/config.toml
systemctl enable --now containerd
```

The `grep` command should show the enabled `SystemdCgroup` setting. If it does not, correct the containerd configuration before continuing.

### 3. Install Kubernetes Packages on All Nodes

Configure the v1.36 package repository and install kubelet, kubeadm, and kubectl:

```bash
cat > /etc/yum.repos.d/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet
```

The kubelet may restart while waiting for kubeadm configuration; that is expected before cluster initialization.

### 4. Configure Firewalld

Keep firewalld enabled and add only the required cluster traffic. Also permit SSH and any site-specific management traffic. These rules assume Calico's default IP-in-IP encapsulation/BGP routing; if you choose another Calico dataplane, open its documented node-to-node ports instead.

#### Control-plane nodes

Run on cp01, cp02, and cp03:

```bash
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10257/tcp
firewall-cmd --permanent --add-port=10259/tcp
firewall-cmd --permanent --add-protocol=vrrp
firewall-cmd --permanent --add-port=179/tcp
firewall-cmd --permanent --add-protocol=4
firewall-cmd --reload
```

HAProxy statistics listen on TCP/8404, which is closed by default. If administrators need remote access, replace `ADMIN_CIDR` with a trusted administrator address or subnet and add this rich rule on each control-plane node:

```bash
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="ADMIN_CIDR" port port="8404" protocol="tcp" accept'
firewall-cmd --reload
```

#### Worker nodes

Run on worker01, worker02, and worker03:

```bash
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=30000-32767/tcp
firewall-cmd --permanent --add-port=30000-32767/udp
firewall-cmd --permanent --add-port=179/tcp
firewall-cmd --permanent --add-protocol=4
firewall-cmd --reload
```

Calico BGP and IP-in-IP traffic must be allowed between all cluster nodes. If using Calico VXLAN instead, allow UDP/4789 between nodes and configure the Calico pool accordingly. Apply equivalent rules in any upstream network firewall or security groups.

### 5. Configure HAProxy and Keepalived on Control Planes

Install both services on cp01, cp02, and cp03. Permit HAProxy to bind the VIP even when it is not currently assigned to that node:

```bash
dnf install -y haproxy keepalived
echo 'net.ipv4.ip_nonlocal_bind = 1' > /etc/sysctl.d/99-vip.conf
sysctl --system
```

Put the following in `/etc/haproxy/haproxy.cfg` on all three control-plane nodes. Replace the statistics password. Remote access to port 8404 is optional and source-restricted as described above.

```text
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
	stats auth admin:REPLACE_WITH_A_STRONG_PASSWORD
```

Create `/etc/keepalived/keepalived.conf` on each control-plane node. Replace `ens160` with that host's actual cluster-facing interface (`ip -br address`), and replace `CHANGE01` with the same private, at-most-eight-character password on all three nodes. Keepalived's PASS authentication is not a substitute for network isolation.

#### cp01

```text
vrrp_script check_haproxy {
	script "pidof haproxy"
	interval 2
	weight -30
	fall 2
	rise 2
}

vrrp_instance VI_1 {
	state MASTER
	interface ens160
	virtual_router_id 51
	priority 100
	advert_int 1
	unicast_src_ip 192.168.10.11
	unicast_peer {
		192.168.10.12
		192.168.10.13
	}
	authentication {
		auth_type PASS
		auth_pass CHANGE01
	}
	virtual_ipaddress {
		192.168.10.100/24
	}
	track_script {
		check_haproxy
	}
}
```

#### cp02

Use the same `vrrp_script` block as cp01. In `vrrp_instance VI_1`, set:

```text
	state BACKUP
	interface ens160
	virtual_router_id 51
	priority 90
	advert_int 1
	unicast_src_ip 192.168.10.12
	unicast_peer {
		192.168.10.11
		192.168.10.13
	}
```

Use the same `authentication`, `virtual_ipaddress`, and `track_script` blocks as cp01.

#### cp03

Use the same `vrrp_script` block as cp01. In `vrrp_instance VI_1`, set:

```text
	state BACKUP
	interface ens160
	virtual_router_id 51
	priority 80
	advert_int 1
	unicast_src_ip 192.168.10.13
	unicast_peer {
		192.168.10.11
		192.168.10.12
	}
```

Use the same `authentication`, `virtual_ipaddress`, and `track_script` blocks as cp01. The negative script weight is large enough for a failed HAProxy on the current VIP owner to lower its priority below the next healthy node.

Validate and start the services on all three control-plane nodes:

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable --now haproxy keepalived
```

Before initializing Kubernetes, confirm `192.168.10.100` is assigned to exactly one control-plane node and reachable from every node. A HAProxy backend check for port 6443 will remain down until the API servers are initialized.

### 6. Initialize the Cluster

On cp01, initialize the first control plane. The pod CIDR is deliberately `10.244.0.0/16`; it does not overlap this environment's `192.168.10.0/24` node network. The explicit CRI socket selects containerd.

```bash
kubeadm init \
  --kubernetes-version="$(kubeadm version -o short)" \
  --control-plane-endpoint="kubernetes-api.company.local:6443" \
  --apiserver-advertise-address=192.168.10.11 \
  --cri-socket=unix:///run/containerd/containerd.sock \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16
```

Save the `kubeadm join` command, discovery-token CA hash, and certificate key printed by kubeadm. Treat the certificate key as sensitive and join the other control planes before the uploaded certificate key expires.

Configure kubectl on cp01 as the user who will administer the cluster:

```bash
mkdir -p "$HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

### 7. Join the Remaining Nodes

On cp02 and cp03, run the control-plane join command generated on cp01, substituting the node-specific advertise address:

```bash
kubeadm join kubernetes-api.company.local:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<DISCOVERY_CA_HASH> \
  --control-plane \
  --certificate-key <CERTIFICATE_KEY> \
  --apiserver-advertise-address=<THIS_NODES_IP> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

Use `192.168.10.12` on cp02 and `192.168.10.13` on cp03. On each worker, run the standard worker join command printed by `kubeadm init`, adding the containerd socket if it is not already included:

```bash
kubeadm join kubernetes-api.company.local:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<DISCOVERY_CA_HASH> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

If the bootstrap token expires before all nodes join, create a fresh join command on cp01 with `kubeadm token create --print-join-command`. If the uploaded control-plane certificates have expired, run `kubeadm init phase upload-certs --upload-certs` on cp01 and use the newly printed certificate key.

### 8. Install Calico and Verify

Run on cp01 after the control planes have joined. Download the pinned manifest, set its IP pool to the same CIDR given to kubeadm, then apply it. This avoids Calico creating its default `192.168.0.0/16` pool, which overlaps the node network here.

```bash
curl -fsSLo calico.yaml \
  https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/calico.yaml
sed -i '/# - name: CALICO_IPV4POOL_CIDR/{s/# - name:/- name:/; n; s/#   value:/  value:/; s#192\.168\.0\.0/16#10.244.0.0/16#;}' calico.yaml
grep -A1 'CALICO_IPV4POOL_CIDR' calico.yaml
kubectl apply -f calico.yaml
```

The `grep` output must show an uncommented `CALICO_IPV4POOL_CIDR` with value `10.244.0.0/16`. If not, edit the `calico-node` DaemonSet environment in `calico.yaml` before applying it.

Verify the API endpoint, nodes, and system pods:

```bash
curl -k https://kubernetes-api.company.local:6443/readyz
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

All six nodes should become `Ready` after Calico is running. Confirm that the VIP remains assigned to one control-plane node. Test failover in a maintenance window by stopping HAProxy on the current VIP owner; verify that another control-plane node assumes the VIP and that the API endpoint recovers, then restart HAProxy.