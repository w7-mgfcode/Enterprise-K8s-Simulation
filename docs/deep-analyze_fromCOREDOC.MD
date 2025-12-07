Deep Analysis: Enterprise Kubernetes Deployment Design
� Executive Summary
This is a production-grade, multi-datacenter Kubernetes platform design for 2Connect, featuring:

Stretched cluster architecture across 3 datacenters
Bare-metal deployment (no virtualization layer)
High availability with full DC failover capability
NIS2 compliance and Zero Trust security model
Hybrid storage strategy (Longhorn + Dell PowerScale)

�️ HARDWARE SPECIFICATIONS
Control Plane Servers (Master Nodes)
Model: Dell PowerEdge R660xs (1U)

Quantity: 6 units (3 PROD + 3 DEV)
CPU: Intel Xeon Silver 4509Y (8 cores/16 threads @ 2.6GHz)
RAM: 64 GB (4×16GB RDIMM @ 5600MT/s)
Storage: 2×480GB SSD SATA (RAID1 for OS)
Network:

1× Broadcom 57414 Dual Port 25GbE SFP28
1× Broadcom 5720 Dual Port 1GbE (management)

Management: iDRAC9 Enterprise 16G
Power: Redundant 1+1, 700W

Worker Node Servers
Model: Dell PowerEdge R760 (2U)

Quantity: 12 units (8 PROD + 4 DEV)
CPU: 2× Intel Xeon Silver 4416+ (40 cores/80 threads total @ 2.0GHz)
RAM: 1 TB (16×64GB RDIMM @ 5600MT/s)
Storage:

2×480GB M.2 SSD (RAID1 for OS)
8×960GB SSD SATA (RAID6 for Longhorn)

Network:

1× Broadcom 57414 Dual Port 25GbE SFP28
1× Broadcom 5720 Dual Port 1GbE

Management: iDRAC9 Enterprise 16G
Power: Redundant 1+1, 1100W

Central Storage System
Model: Dell PowerScale A300 Cluster

Configuration: 4-node cluster
Usable Capacity: 80 TiB
Network: 2×25GbE SFP28 per node
Dedicated Switches: 2× Dell S4112F-ON
Protocols: NFS (file) + S3 (object storage)

�️ ARCHITECTURE DESIGN
Cluster Topology
PROD Cluster (Stretched)

3 Datacenters: DC10-Kozma, DC-Petzvál, DC-Gyömrői
Control Plane: 1-1-1 distribution (3 masters, one per DC)
Worker Nodes: 4-4-0 distribution (8 workers in DC1 & DC2 only)
etcd: Stacked mode, quorum requires 2 nodes
High Availability: Survives full datacenter failure

DEV Cluster (Single DC)

Location: DC10-Kozma only
Control Plane: 3 masters
Worker Nodes: 4 workers
Isolation: Completely separate from PROD

� NETWORK ARCHITECTURE
VLAN Segmentation

Management VLAN

iDRAC ports, switch/firewall management

Host Network

OS network interfaces
PowerScale data ports

Container Network

Pod IP addresses (managed by Cilium)
WireGuard encrypted overlay

Key Components

CNI: Cilium (eBPF-based)

Network policies
Transparent encryption (WireGuard)
Load balancing (BGP/L2)

Ingress: NGINX Ingress Controller
API Gateway: Gravitee
Routing: Fortigate firewall (inter-VLAN)

� STORAGE ARCHITECTURE
Two-Tier Storage Strategy
Tier 1: Distributed Block Storage (Longhorn)

Use Case: Stateful applications requiring RWO
Technology: Longhorn CSI
Replication: 3 replicas across worker nodes
Performance: High-performance SSD-backed
Examples: PostgreSQL, Kafka, Prometheus

Tier 2: Centralized Storage (Dell PowerScale)

NFS (RWX): Shared file systems

GitLab shared data, CMS systems

S3 (Object): Unstructured data

Loki logs, Harbor images, CI/CD artifacts

Isolation: Separate Access Zones for DEV/PROD

StorageClass Configuration
yaml- longhorn (default) → Block/RWO → General stateful apps

- powerscale-nfs-prod → File/RWX → PROD shared files
- powerscale-nfs-dev → File/RWX → DEV shared files

� SECURITY ARCHITECTURE (Zero Trust + NIS2)
Defense Layers

1. DevSecOps Pipeline

SonarQube: Static code analysis
Trivy: Container image vulnerability scanning
Harbor: Private registry with integrated scanning

2. Server Security

Wazuh: Host-based IDS/SIEM

File Integrity Monitoring (FIM)
OS vulnerability detection
Log analysis

3. Network Security

Cilium:

Micro-segmentation (default deny)
NetworkPolicy enforcement
Node-to-node encryption (WireGuard)

4. Cluster Security

RBAC: Role-based access control
CIS Benchmark: Automated compliance (kube-bench)
Admission Controllers: Policy enforcement

5. Data Security

Vault: Centralized secrets management
Cert-Manager: Automated TLS certificate lifecycle
Keycloak: SSO/IAM (AD integration)

� PLATFORM TECHNOLOGY STACK
Core Platform

OS: Ubuntu 24.04 LTS (bare metal)
Kubernetes: Latest stable (kubeadm deployment)
Automation: Ansible (IaC)
HA: kube-vip (Control Plane VIP)

Networking

CNI: Cilium
Ingress: NGINX Ingress Controller
API Gateway: Gravitee
Service Mesh: Cilium (eBPF-native)

Storage

Block: Longhorn CSI
File/Object: Dell PowerScale CSI
Backup: TBD (separate document)

Observability

Metrics: Prometheus → Grafana Mimir (long-term)
Logs: Loki + Grafana Alloy agents
Visualization: Grafana
Alerting: Prometheus Alertmanager
External: Icinga (NOC monitoring via NRPE)

CI/CD Pipeline

SCM: GitLab
Build: GitLab CI/CD
Artifacts: Nexus Repository Manager
Container Registry: Harbor
Code Quality: SonarQube
Scanning: Trivy
Deployment: Ansible playbooks (CI-driven)

Databases & Messaging

PostgreSQL: CloudNative-PG operator
Kafka: Strimzi operator

Operations

Node Maintenance: Kured (automated reboots)
Problem Detection: Node Problem Detector
Virtualization: KubeVirt (VM support)
GUI Management: Lens Desktop

⚙️ INSTALLATION & OPERATIONS
Deployment Methodology
Phase 1: OS Installation (Manual + Ansible)
Prerequisites per node:

Ubuntu 24.04 LTS installation
Disk partitioning (OS + Longhorn separate)
Basic hardening

Ansible Playbook Tasks:

Install runtime: containerd
Install K8s components: kubelet, kubeadm, kubectl
Configure kernel parameters (sysctl)
Deploy agents:

Nagios NRPE (Icinga monitoring)
OCS Inventory (asset management)
Wazuh (security monitoring)
rsyslog (central logging)

Phase 2: Cluster Bootstrap (kubeadm + Ansible)

Initialize first control plane with kube-vip
Join additional control planes (etcd stacked)
Join worker nodes
Install Cilium CNI
Verify cluster health

Phase 3: Platform Components (GitLab/Ansible)
Deployment order:

Storage: Longhorn, PowerScale CSI
Networking: NGINX Ingress, Gravitee
Security: Vault, Keycloak, Cert-Manager
Observability: Prometheus stack, Loki, Grafana
CI/CD: GitLab, Harbor, SonarQube, Nexus
Databases: CloudNative-PG
Operations: NPD, Kured

Lifecycle Management

OS Updates: Automated via Ansible + Kured
K8s Upgrades: kubeadm upgrade (Ansible-orchestrated)
Component Updates: GitOps via GitLab CI
Monitoring: 24/7 via Prometheus + Grafana + Icinga

� ENTERPRISE INTEGRATIONS
Identity & Access

Active Directory: Primary identity source

Keycloak federation (LDAP/OIDC)
PowerScale authentication

Monitoring

Icinga (NOC): Physical server monitoring via NRPE
OCS Inventory: Hardware/software asset tracking
Syslog-ng Store Box: Centralized audit logs

Security

Wazuh: Host-level security events
Vault: Dynamic secrets for AD service accounts

⚠️ RISKS & CONSIDERATIONS
Critical Risks

1. Network Latency (RTT)

Issue: Stretched cluster etcd performance depends on DC-DC RTT
Threshold: >10-15ms may cause instability
Mitigation: Pre-deployment network testing required

2. PowerScale Single Point of Failure

Issue: No multi-DC replication configured
Impact: Full data loss if DC failure
Recommendation: Deploy second PowerScale + SyncIQ replication

Open Questions

Policy enforcement engine (Kyverno/OPA)?
DRP document finalization
Backup strategy documentation

� KEY METRICS & SIZING
Total Infrastructure

Servers: 18 physical servers
CPU Cores: 744 total cores (Control Plane: 96, Workers: 648)
RAM: 12.38 TB total memory
Storage:

Longhorn: ~90 TB raw (RAID6 on workers)
PowerScale: 80 TiB usable

Network: 25GbE spine, 1GbE management

Expected Capacity

PROD Worker Nodes: 8 × 1TB RAM = 8TB workload capacity
Pod Density: ~30-50 pods per worker (approx 240-400 total)
Storage IOPS: High (SSD-based Longhorn)

� KEYWORDS FOR ANSIBLE AUTOMATION
Infrastructure:
bare-metal, dell-poweredge, ubuntu-24.04, idrac, raid-configuration
Kubernetes:
kubeadm, stacked-etcd, kube-vip, stretched-cluster, control-plane-ha
Networking:
cilium-cni, wireguard-encryption, network-policies, nginx-ingress, bgp-routing
Storage:
longhorn-csi, dell-powerscale, nfs-provisioner, s3-compatible, dynamic-provisioning
Security:
wazuh-agent, vault-integration, keycloak-sso, rbac-policies, cis-benchmark, nis2-compliance
Operations:
ansible-playbooks, gitops, prometheus-monitoring, loki-logging, kured-reboot
CI/CD:
gitlab-runner, harbor-registry, trivy-scanner, sonarqube, nexus-artifacts
Integrations:
active-directory, icinga-nrpe, ocs-inventory, rsyslog-forwarding

✅ CRITICAL SUCCESS FACTORS

Pre-deployment network testing (DC-DC RTT validation)
Ansible playbook development (OS hardening, K8s bootstrap, component deployment)
Storage isolation (DEV/PROD Access Zones)
Security baseline (CIS compliance from day 1)
Comprehensive monitoring (Prometheus + Icinga dual-layer)
Documentation (runbooks for operations team)
DR planning (backup strategy + PowerScale replication)

This is an enterprise-grade, battle-tested architecture that follows Kubernetes best practices with strong focus on security, observability, and automation. The design is production-ready for mission-critical workloads. �
