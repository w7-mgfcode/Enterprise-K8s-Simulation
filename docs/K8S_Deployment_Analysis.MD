# � Enterprise Kubernetes Deployment - Deep Analysis

**Document:** K8s Deployment Design Document Analysis  
**Organization:** 2Connect  
**Date:** November 11, 2025  
**Architecture:** Multi-Datacenter Stretched Cluster

---

## � Executive Summary

This is a **production-grade, multi-datacenter Kubernetes platform design** for 2Connect, featuring:

- **Stretched cluster architecture** across 3 datacenters
- **Bare-metal deployment** (no virtualization layer)
- **High availability** with full DC failover capability
- **NIS2 compliance** and Zero Trust security model
- **Hybrid storage** strategy (Longhorn + Dell PowerScale)

---

## �️ HARDWARE SPECIFICATIONS

### Control Plane Servers (Master Nodes)

**Model:** Dell PowerEdge R660xs (1U)

| Component      | Specification                                                                         |
| -------------- | ------------------------------------------------------------------------------------- |
| **Quantity**   | 6 units (3 PROD + 3 DEV)                                                              |
| **CPU**        | Intel Xeon Silver 4509Y<br>8 cores / 16 threads @ 2.6GHz                              |
| **RAM**        | 64 GB (4×16GB RDIMM @ 5600MT/s)                                                       |
| **Storage**    | 2×480GB SSD SATA (RAID1 for OS)                                                       |
| **Network**    | • Broadcom 57414 Dual Port 25GbE SFP28<br>• Broadcom 5720 Dual Port 1GbE (management) |
| **Management** | iDRAC9 Enterprise 16G                                                                 |
| **Power**      | Redundant 1+1, Hot-Plug, 700W                                                         |

### Worker Node Servers

**Model:** Dell PowerEdge R760 (2U)

| Component      | Specification                                                               |
| -------------- | --------------------------------------------------------------------------- |
| **Quantity**   | 12 units (8 PROD + 4 DEV)                                                   |
| **CPU**        | 2× Intel Xeon Silver 4416+<br>40 cores / 80 threads total @ 2.0GHz          |
| **RAM**        | 1 TB (16×64GB RDIMM @ 5600MT/s)                                             |
| **Storage**    | • 2×480GB M.2 SSD (RAID1 for OS)<br>• 8×960GB SSD SATA (RAID6 for Longhorn) |
| **Network**    | • Broadcom 57414 Dual Port 25GbE SFP28<br>• Broadcom 5720 Dual Port 1GbE    |
| **Management** | iDRAC9 Enterprise 16G                                                       |
| **Power**      | Redundant 1+1, Hot-Plug, 1100W                                              |

### Central Storage System

**Model:** Dell PowerScale A300 Cluster

| Component              | Specification                    |
| ---------------------- | -------------------------------- |
| **Configuration**      | 4-node cluster                   |
| **Usable Capacity**    | 80 TiB                           |
| **Network**            | 2×25GbE SFP28 per node           |
| **Dedicated Switches** | 2× Dell S4112F-ON                |
| **Protocols**          | NFS (file) + S3 (object storage) |
| **Access Zones**       | DEV and PROD isolated            |

---

## �️ ARCHITECTURE DESIGN

### Cluster Topology

#### PROD Cluster (Stretched Architecture)

**Multi-Datacenter Setup:**

- **DC10-Kozma** (Primary)
- **DC-Petzvál** (Secondary)
- **DC-Gyömrői** (DR/Quorum)

**Component Distribution:**

```
Control Plane (3 masters):
├── DC10-Kozma:    1 master node
├── DC-Petzvál:    1 master node
└── DC-Gyömrői:    1 master node
    └── etcd: Stacked mode, quorum = 2 nodes

Worker Nodes (8 workers):
├── DC10-Kozma:    4 worker nodes
├── DC-Petzvál:    4 worker nodes
└── DC-Gyömrői:    0 worker nodes (Control Plane only)
```

**High Availability Features:**

- Survives full datacenter failure
- kube-vip provides Virtual IP for Control Plane
- Asymmetric worker distribution (4-4-0)

#### DEV Cluster (Single Datacenter)

**Location:** DC10-Kozma only

```
Control Plane: 3 master nodes
Worker Nodes:  4 worker nodes
Isolation:     Complete separation from PROD
```

---

## � NETWORK ARCHITECTURE

### VLAN Segmentation

| VLAN                  | Purpose                    | Connected Devices                                  |
| --------------------- | -------------------------- | -------------------------------------------------- |
| **Management VLAN**   | Physical device management | iDRAC ports, switch/firewall management interfaces |
| **Host Network**      | Cluster base communication | Server OS interfaces, PowerScale data ports        |
| **Container Network** | Pod-to-pod communication   | Pod IP addresses (Cilium-managed)                  |

### Network Components

#### Cilium (CNI - Container Network Interface)

**Technology:** eBPF-based networking

**Responsibilities:**

- Pod IP address allocation
- NetworkPolicy enforcement (micro-segmentation)
- Node-to-node encryption (WireGuard)
- Load balancing (BGP/L2 modes)
- Service mesh capabilities

#### Traffic Flow

```
External Request
    ↓
Fortigate Firewall (VLAN routing)
    ↓
NGINX Ingress Controller (HTTP/S termination)
    ↓
Gravitee API Gateway (API management)
    ↓
Cilium Network (encrypted overlay)
    ↓
Application Pods
```

**Key Features:**

- Default deny network policies
- Transparent WireGuard encryption
- Cilium Hubble UI for observability

---

## � STORAGE ARCHITECTURE

### Two-Tier Storage Strategy

#### Tier 1: Distributed Block Storage (Longhorn)

**Use Case:** Stateful applications requiring exclusive access (RWO)

| Aspect           | Details                        |
| ---------------- | ------------------------------ |
| **Technology**   | Longhorn CSI Driver            |
| **Storage Type** | Block (SCSI)                   |
| **Access Mode**  | ReadWriteOnce (RWO)            |
| **Replication**  | 3 replicas across worker nodes |
| **Backend**      | Worker node SSD disks (RAID6)  |
| **Performance**  | High-performance, low-latency  |

**Typical Workloads:**

- CloudNative-PG (PostgreSQL databases)
- Strimzi (Kafka message storage)
- Prometheus (metrics storage)
- High I/O stateful applications

#### Tier 2: Centralized Storage (Dell PowerScale)

**Use Case:** Shared file systems and object storage

##### NFS (Network File System)

| Aspect          | Details                                         |
| --------------- | ----------------------------------------------- |
| **Protocol**    | NFS v3/v4                                       |
| **Access Mode** | ReadWriteMany (RWX)                             |
| **Integration** | PowerScale CSI Driver                           |
| **Use Cases**   | GitLab shared data, CMS systems, shared configs |

##### S3 (Object Storage)

| Aspect            | Details                           |
| ----------------- | --------------------------------- |
| **Protocol**      | S3-compatible API                 |
| **Access Method** | Direct API calls (not PVC)        |
| **Storage Path**  | Dedicated buckets per environment |

**S3 Bucket Configuration:**

```
DEV Environment:
├── Access Zone: az-k8s-dev
├── Base Path: /ifs/k8s-dev/s3/
└── Buckets:
    └── loki-chunks (Loki log storage)

PROD Environment:
├── Access Zone: az-k8s-prod
├── Base Path: /ifs/k8s-prod/s3/
└── Buckets:
    ├── loki-chunks (Loki log storage)
    ├── harbor-images (Container images)
    └── gitlab-artifacts (CI/CD artifacts)
```

### StorageClass Configuration

| StorageClass Name     | Backend    | Type/Access | Use Case                         |
| --------------------- | ---------- | ----------- | -------------------------------- |
| `longhorn` (default)  | Longhorn   | Block/RWO   | General stateful apps, databases |
| `powerscale-nfs-prod` | PowerScale | File/RWX    | PROD shared file systems         |
| `powerscale-nfs-dev`  | PowerScale | File/RWX    | DEV shared file systems          |

### Storage Isolation

**Environment Separation:**

- Separate Access Zones (az-k8s-dev, az-k8s-prod)
- Separate directory trees (/ifs/k8s-dev, /ifs/k8s-prod)
- Separate authentication providers (AD integration)

---

## � SECURITY ARCHITECTURE

### Zero Trust + NIS2 Compliance

**Guiding Principles:**

- Least privilege access
- Defense in depth
- Continuous vulnerability management
- Comprehensive audit logging

### Security Layers

#### Layer 1: DevSecOps Pipeline Security

**Components:**

| Tool          | Function                         | Integration Point                 |
| ------------- | -------------------------------- | --------------------------------- |
| **SonarQube** | Static code analysis             | GitLab CI pipeline                |
| **Trivy**     | Container vulnerability scanning | CI pipeline + Harbor              |
| **Harbor**    | Private registry with scanning   | Image storage + admission control |

**Process Flow:**

```
Code Push → SonarQube Scan → Build → Trivy Scan → Harbor → Kubernetes
```

#### Layer 2: Server Security (Host Level)

**Wazuh Security Platform:**

| Feature                             | Purpose                          |
| ----------------------------------- | -------------------------------- |
| **File Integrity Monitoring (FIM)** | Detect unauthorized file changes |
| **Host-based IDS (HIDS)**           | Intrusion detection              |
| **Vulnerability Detection**         | OS-level CVE scanning            |
| **Log Analysis**                    | Security event correlation       |
| **Compliance Monitoring**           | CIS benchmark checks             |

**Deployment:** Agent on every node, centralized management

#### Layer 3: Network Security

**Cilium Network Policies:**

```yaml
Default Behavior: DENY ALL
Explicit Allow: NetworkPolicy objects only
Encryption: WireGuard (node-to-node)
```

**Features:**

- Micro-segmentation (namespace/pod level)
- L3/L4/L7 policy enforcement
- Transparent encryption
- Egress gateway control

#### Layer 4: Cluster & Container Security

**Kubernetes RBAC (Role-Based Access Control):**

| Role                       | Permissions                  | Scope               |
| -------------------------- | ---------------------------- | ------------------- |
| **Platform Ops**           | Physical infrastructure only | No kubectl access   |
| **Cluster Ops**            | cluster-admin                | Entire cluster      |
| **Developers**             | Namespace-specific           | Own namespaces only |
| **SecOps**                 | read-only                    | Cluster-wide audit  |
| **CI/CD Service Accounts** | Limited deployment           | Specific namespaces |

**CIS Benchmark Compliance:**

- Automated scanning with `kube-bench`
- API Server hardening
- etcd encryption at rest
- Kubelet security configuration

**Image Security:**

- Harbor admission webhooks
- Only signed images allowed
- Continuous re-scanning
- Policy enforcement

#### Layer 5: Data Security & Secrets Management

**HashiCorp Vault:**

| Feature                    | Implementation                  |
| -------------------------- | ------------------------------- |
| **Dynamic Secrets**        | On-demand credential generation |
| **Centralized Management** | Single source of truth          |
| **Rotation**               | Automated credential rotation   |
| **Audit Logging**          | Complete access history         |
| **Integration**            | Kubernetes ServiceAccounts      |

**Cert-Manager:**

- Automated TLS certificate lifecycle
- Let's Encrypt integration
- Internal CA support
- Auto-renewal (no expired certs)

**Keycloak (SSO/IAM):**

- Active Directory federation (LDAP)
- OIDC authentication
- Centralized user management
- MFA support

---

## � PLATFORM TECHNOLOGY STACK

### Core Platform Components

#### Operating System & Orchestration

| Component      | Version       | Purpose                   |
| -------------- | ------------- | ------------------------- |
| **Ubuntu**     | 24.04 LTS     | Base OS (bare metal)      |
| **Kubernetes** | Latest stable | Container orchestration   |
| **kubeadm**    | Latest        | Cluster bootstrap         |
| **Ansible**    | Latest        | Infrastructure automation |
| **kube-vip**   | Latest        | Control Plane HA (VIP)    |

#### Cluster Operations

| Component                 | Purpose                             |
| ------------------------- | ----------------------------------- |
| **Node Problem Detector** | Hardware/software health monitoring |
| **Kured**                 | Automated safe node reboots         |
| **Metrics Server**        | Resource metrics (CPU/RAM)          |

### Networking Stack

| Component         | Technology | Purpose                              |
| ----------------- | ---------- | ------------------------------------ |
| **Cilium**        | eBPF CNI   | Pod networking, policies, encryption |
| **NGINX Ingress** | -          | HTTP/S traffic ingress               |
| **Gravitee**      | -          | API Gateway & management             |
| **Cilium Hubble** | -          | Network observability UI             |

### Storage Stack

| Component          | Type        | Purpose                        |
| ------------------ | ----------- | ------------------------------ |
| **Longhorn**       | Block CSI   | Distributed replicated storage |
| **PowerScale CSI** | File/Object | NFS and S3 integration         |

### Observability Stack (PLG)

#### Metrics (Prometheus → Mimir)

```
┌─────────────────────────────────────────┐
│  PROD/DEV Clusters (Local Prometheus)  │
│  ├── Metrics collection (6-24h local)  │
│  ├── Alerting rules evaluation         │
│  └── Forward to Mimir                  │
└──────────────────┬──────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│  Grafana Mimir (Central Long-term)     │
│  ├── S3 backend (PowerScale)           │
│  ├── Horizontal scaling                │
│  └── Global query endpoint             │
└──────────────────┬──────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│  Grafana (Visualization)               │
└─────────────────────────────────────────┘
```

**Components:**

- **Prometheus:** Metric collection & alerting
- **Grafana Mimir:** Long-term metric storage (S3-backed)
- **Grafana:** Unified dashboards
- **Alertmanager:** Alert routing & deduplication

#### Logging (Loki Stack)

```
┌─────────────────────────────────────────┐
│  Grafana Alloy Agents (on every node)  │
│  ├── Application logs (stdout/stderr)  │
│  ├── System logs (journald)            │
│  └── Audit logs (K8s API)              │
└──────────────────┬──────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│  Grafana Loki                          │
│  ├── Index: Longhorn (fast SSD)       │
│  └── Chunks: PowerScale S3 (archival)  │
└──────────────────┬──────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│  Grafana (Log exploration)             │
└─────────────────────────────────────────┘
```

**Features:**

- Label-based indexing (cost-efficient)
- Hybrid storage (SSD + S3)
- Fast search & filtering
- Retention policies

### CI/CD Pipeline

#### Source Code Management

| Component         | Purpose                  |
| ----------------- | ------------------------ |
| **GitLab**        | SCM, CI/CD orchestration |
| **GitLab Runner** | Job execution            |

#### Artifact Management

| Component            | Type      | Purpose                         |
| -------------------- | --------- | ------------------------------- |
| **Nexus Repository** | Universal | Maven, npm, Python packages     |
| **Harbor**           | Container | Docker/OCI images with scanning |

#### Code Quality & Security

| Component     | Stage        | Purpose                |
| ------------- | ------------ | ---------------------- |
| **SonarQube** | CI           | Static code analysis   |
| **Trivy**     | CI + Runtime | Vulnerability scanning |

#### CI/CD Flow

```
┌──────────────────────────────────────────────────────────┐
│  CONTINUOUS INTEGRATION (CI)                            │
├──────────────────────────────────────────────────────────┤
│  1. Code Push (GitLab)                                  │
│  2. SonarQube Scan → Code Quality Gate                 │
│  3. Build → Pull dependencies (Nexus)                  │
│  4. Unit Tests                                          │
│  5. Build Container Image                              │
│  6. Trivy Scan → Vulnerability Check                   │
│  7. Push to Harbor (if passed)                         │
└──────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────┐
│  CONTINUOUS DEPLOYMENT (CD)                             │
├──────────────────────────────────────────────────────────┤
│  8. [AUTO] Deploy to DEV                               │
│     └── GitLab CI calls Ansible playbook              │
│         └── Ansible applies K8s manifests (kubectl)    │
│                                                         │
│  9. [MANUAL APPROVAL] Deploy to PROD                   │
│     └── Same process, human gate                       │
└──────────────────────────────────────────────────────────┘
```

### Database & Messaging

| Component          | Type                | Purpose                     |
| ------------------ | ------------------- | --------------------------- |
| **CloudNative-PG** | PostgreSQL Operator | Managed PostgreSQL clusters |
| **Strimzi**        | Kafka Operator      | Managed Kafka clusters      |

### Additional Capabilities

| Component        | Purpose                    |
| ---------------- | -------------------------- |
| **KubeVirt**     | VM workloads on Kubernetes |
| **Lens Desktop** | GUI cluster management     |

---

## ⚙️ INSTALLATION & OPERATIONS

### Deployment Methodology

#### Phase 1: OS Installation & Configuration

**Manual Steps:**

1. Install Ubuntu 24.04 LTS (bare metal)
2. Configure disk partitioning:
   - OS: RAID1 (2×480GB SSD)
   - Longhorn: RAID6 (8×960GB SSD on workers)
3. Basic network configuration

**Ansible Automation:**

```yaml
# Ansible Playbook Tasks:
├── Container Runtime
│   └── Install & configure containerd
│
├── Kubernetes Components
│   ├── kubelet
│   ├── kubeadm
│   └── kubectl
│
├── Monitoring Agents
│   ├── Nagios NRPE (Icinga integration)
│   └── OCS Inventory (asset tracking)
│
├── Security Agents
│   └── Wazuh agent
│
├── System Configuration
│   ├── Kernel parameters (sysctl)
│   ├── rsyslog (central logging)
│   └── System hardening (CIS baseline)
│
└── Verification
└── Readiness checks
```

#### Phase 2: Cluster Bootstrap

**Control Plane Initialization:**

```bash
# Step 1: Initialize first master (kube-vip + kubeadm)
kubeadm init --control-plane-endpoint=<VIP>:6443 \
             --upload-certs \
             --pod-network-cidr=10.244.0.0/16

# Step 2: Install Cilium CNI
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set encryption.enabled=true \
  --set encryption.type=wireguard

# Step 3: Join additional control planes
kubeadm join <VIP>:6443 --control-plane \
  --certificate-key <cert-key>

# Step 4: Join worker nodes
kubeadm join <VIP>:6443 --token <token>
```

**Verification:**

```bash
kubectl get nodes
kubectl get pods -A
kubectl top nodes
```

#### Phase 3: Platform Components Deployment

**Deployment Order (via GitLab CI + Ansible):**

```
1. Storage Layer
   ├── Longhorn
   └── PowerScale CSI Driver

2. Network Layer
   ├── NGINX Ingress Controller
   └── Gravitee API Gateway

3. Security Layer
   ├── Vault
   ├── Keycloak
   └── Cert-Manager

4. Observability Layer
   ├── Prometheus Stack
   ├── Grafana Mimir
   ├── Loki Stack
   └── Grafana

5. CI/CD Layer
   ├── GitLab
   ├── Harbor
   ├── SonarQube
   └── Nexus

6. Data Layer
   ├── CloudNative-PG
   └── Strimzi

7. Operations Layer
   ├── Node Problem Detector
   ├── Kured
   └── KubeVirt
```

### Lifecycle Management

#### OS Maintenance

**Automated Update Process:**

```
Scheduled Ansible Playbook (weekly)
    ↓
APT Package Updates (security patches)
    ↓
Reboot Required?
    ↓
Kured Daemon (Kubernetes Reboot Daemon)
├── Drain node (evict pods)
├── Reboot server
├── Wait for node ready
└── Uncordon node
    ↓
Next node (one at a time)
```

**Safety Features:**

- Respects PodDisruptionBudgets
- Only one node at a time
- Automatic pod rescheduling

#### Kubernetes Version Upgrades

**Process (kubeadm + Ansible):**

1. **Preparation:**

   - Test in DEV cluster first
   - Review release notes
   - Backup etcd cluster

2. **Control Plane Upgrade:**

```bash
# For each master (one at a time):
kubeadm upgrade plan
kubeadm upgrade apply v1.XX.X
systemctl restart kubelet
```

3. **Worker Node Upgrade:**

```bash
# For each worker (Ansible-orchestrated):
kubectl drain <node> --ignore-daemonsets
kubeadm upgrade node
systemctl restart kubelet
kubectl uncordon <node>
```

4. **Verification:**
   - Check cluster health
   - Verify workload functionality
   - Monitor for issues

#### Component Updates

**GitOps Workflow:**

```
Update Config Repository (Git)
    ↓
GitLab CI Pipeline Triggered
    ↓
Ansible Playbook Execution
    ↓
kubectl apply (rolling update)
    ↓
Automated Health Checks
```

---

## � ENTERPRISE INTEGRATIONS

### Active Directory Integration

**Integration Points:**

| System              | Integration Type | Purpose                         |
| ------------------- | ---------------- | ------------------------------- |
| **Dell PowerScale** | AD Domain Join   | File/object storage permissions |
| **Keycloak**        | LDAP Federation  | User authentication (SSO)       |
| **Grafana**         | LDAP Auth        | Dashboard access                |
| **GitLab**          | LDAP Auth        | Code repository access          |

**Authentication Flow:**

```
User Login Attempt
    ↓
Keycloak (OIDC Provider)
    ↓
Active Directory (LDAP)
    ↓
Token Issued (JWT)
    ↓
Kubernetes API (OIDC validation)
    ↓
RBAC Authorization
```

### Monitoring Integration (NOC)

**Icinga Integration:**

```
┌─────────────────────────────────────┐
│  Kubernetes Nodes                   │
│  ├── Nagios NRPE Agent (port 5666) │
│  └── Check scripts                  │
└──────────────────┬──────────────────┘
                   ↓
┌─────────────────────────────────────┐
│  Icinga Master (Central NOC)        │
│  ├── Host monitoring (ping, SSH)   │
│  ├── Service checks (disk, load)   │
│  └── Alerting                       │
└─────────────────────────────────────┘
```

**Monitored Checks:**

- Server reachability (ICMP)
- SSH service availability
- Disk space utilization
- CPU/memory load
- Service status (kubelet, containerd)

### Asset Management

**OCS Inventory Integration:**

```
OCS Agent (on every node)
    ↓
Periodic Inventory Scan (daily)
    ↓
Data Collection:
├── Hardware (CPU, RAM, disks, NICs)
├── Software (installed packages)
├── Serial numbers
└── Network configuration
    ↓
Central OCS Server (CMDB)
```

**Benefits:**

- Automated license tracking
- Hardware lifecycle management
- Compliance reporting

### Central Logging

**Syslog Integration:**

```
Ubuntu rsyslog (on every node)
    ↓
System Events:
├── Kernel messages
├── Authentication logs
├── Service starts/stops
└── Security events
    ↓
Central Syslog-ng Store Box
    ↓
Long-term Audit Storage
```

**Purpose:**

- Compliance auditing (NIS2)
- Security incident investigation
- Immutable log trail

---

## ⚠️ RISKS & MITIGATION STRATEGIES

### Critical Risks

#### 1. Network Latency (Stretched Cluster)

**Risk Description:**

- etcd consensus requires low latency between nodes
- High DC-DC RTT can cause cluster instability

**Impact:**

- Control plane performance degradation
- Potential split-brain scenarios
- Increased leader election time

**Threshold:**

- **Acceptable:** <5ms RTT
- **Warning:** 5-10ms RTT
- **Critical:** >10ms RTT

**Mitigation:**

```
Pre-Deployment:
├── Network latency testing (ping, iperf3)
├── Dedicated DC-DC links (no shared internet)
└── QoS policies for control plane traffic

Monitoring:
├── Prometheus metrics (etcd_network_peer_round_trip_time_seconds)
├── Alerting on high latency
└── Dashboard for real-time visibility

Contingency:
└── Consider control plane in single DC if RTT >10ms
```

#### 2. PowerScale Single Point of Failure

**Risk Description:**

- PowerScale only in one datacenter
- No multi-DC replication configured
- Full data loss on DC failure

**Impact:**

- Loss of all logs (Loki chunks)
- Loss of CI/CD artifacts
- Loss of Harbor container images
- Loss of shared file data

**Mitigation:**

**Short-term:**

```
├── Regular backups to external system
├── Critical data replication to worker node volumes
└── RTO/RPO analysis
```

**Long-term (Recommended):**

```
├── Deploy second PowerScale in DC2
├── Enable SyncIQ replication (async)
├── Automated failover procedures
└── Test disaster recovery regularly
```

#### 3. etcd Quorum Loss

**Risk Description:**

- 3-node etcd requires 2 nodes for quorum
- Single node failure tolerated
- Two simultaneous failures = cluster down

**Mitigation:**

```
├── Automated etcd backups (hourly)
├── Backup storage: separate system
├── Documented recovery procedures
├── Regular DR drills
└── Consider 5-node etcd for PROD (future)
```

### Medium Risks

#### 4. Certificate Expiration

**Risk:** TLS certificates expire, causing service outages

**Mitigation:**

- Cert-Manager automated renewal
- Prometheus alerting (60/30/7 days before expiry)
- Monitoring dashboard for cert status

#### 5. Storage Capacity Exhaustion

**Risk:** Longhorn or PowerScale runs out of space

**Mitigation:**

- Capacity monitoring (Prometheus)
- Alerts at 70%, 80%, 90%
- Automated cleanup policies (Loki retention)
- Capacity planning (quarterly review)

---

## � KEY METRICS & CAPACITY PLANNING

### Total Infrastructure Inventory

#### Compute Resources

| Component        | Quantity | vCPUs | RAM   | Total vCPUs | Total RAM    |
| ---------------- | -------- | ----- | ----- | ----------- | ------------ |
| **PROD Masters** | 3        | 16    | 64 GB | 48          | 192 GB       |
| **DEV Masters**  | 3        | 16    | 64 GB | 48          | 192 GB       |
| **PROD Workers** | 8        | 80    | 1 TB  | 640         | 8 TB         |
| **DEV Workers**  | 4        | 80    | 1 TB  | 320         | 4 TB         |
| **TOTAL**        | **18**   | -     | -     | **1,056**   | **12.38 TB** |

#### Storage Resources

| Storage Type                    | Technology                             | Raw Capacity | Usable Capacity | RAID     |
| ------------------------------- | -------------------------------------- | ------------ | --------------- | -------- |
| **Worker Local (Longhorn)**     | 12× servers<br>8× 960GB SSD per server | 92 TB        | ~73 TB          | RAID6    |
| **Shared Storage (PowerScale)** | 4-node cluster                         | -            | 80 TiB          | Built-in |
| **TOTAL USABLE**                | -                                      | -            | **~153 TB**     | -        |

#### Network Resources

| Component            | Bandwidth | Redundancy |
| -------------------- | --------- | ---------- |
| **Worker Data NICs** | 25 GbE    | Dual port  |
| **Master NICs**      | 25 GbE    | Dual port  |
| **PowerScale NICs**  | 25 GbE    | 2 per node |
| **Management**       | 1 GbE     | Dual port  |

### Expected Workload Capacity

#### PROD Cluster

```
Worker Nodes: 8 servers
├── Total RAM: 8 TB
├── Reserved for OS/K8s: ~800 GB (10%)
├── Available for workloads: ~7.2 TB
├── Expected pod density: 30-50 pods/node
└── Total pod capacity: 240-400 pods

Storage:
├── Longhorn: ~58 TB usable (PROD workers)
├── PowerScale NFS: ~40 TB allocated
└── PowerScale S3: ~40 TB allocated
```

#### DEV Cluster

```
Worker Nodes: 4 servers
├── Total RAM: 4 TB
├── Reserved for OS/K8s: ~400 GB (10%)
├── Available for workloads: ~3.6 TB
├── Expected pod density: 30-50 pods/node
└── Total pod capacity: 120-200 pods

Storage:
├── Longhorn: ~15 TB usable (DEV workers)
├── PowerScale NFS: ~10 TB allocated
└── PowerScale S3: ~10 TB allocated
```

### Performance Expectations

#### Storage IOPS

| Storage Type       | Expected IOPS | Latency |
| ------------------ | ------------- | ------- |
| **Longhorn (SSD)** | 50,000+       | <5ms    |
| **PowerScale NFS** | 10,000+       | <10ms   |
| **PowerScale S3**  | 5,000+        | <20ms   |

#### Network Throughput

| Path                            | Bandwidth | Usage                  |
| ------------------------------- | --------- | ---------------------- |
| **Pod-to-Pod (same node)**      | ~20 Gbps  | Internal communication |
| **Pod-to-Pod (different node)** | ~18 Gbps  | Cilium overhead        |
| **Storage access (Longhorn)**   | ~20 Gbps  | SSD backend            |
| **Storage access (PowerScale)** | ~18 Gbps  | NFS/S3 traffic         |

---

## � ANSIBLE AUTOMATION KEYWORDS

### Infrastructure Keywords

```yaml
# Server Management
- bare-metal-deployment
- dell-poweredge-r660xs
- dell-poweredge-r760
- idrac9-management
- raid-configuration
- ubuntu-24-04-lts

# Storage
- dell-powerscale-a300
- longhorn-disk-preparation
- partition-layout
- raid1-os-mirror
- raid6-data-storage
```

### Kubernetes Keywords

```yaml
# Cluster Setup
- kubeadm-init
- kubeadm-join
- stacked-etcd
- kube-vip-setup
- control-plane-ha
- stretched-cluster-config

# Components
- containerd-installation
- kubelet-configuration
- kubectl-setup
```

### Networking Keywords

```yaml
# CNI & Network
- cilium-installation
- wireguard-encryption
- network-policy-enforcement
- nginx-ingress-deployment
- bgp-load-balancing
- vlan-configuration

# Security
- cilium-hubble-ui
- network-segmentation
```

### Storage Keywords

```yaml
# Longhorn
- longhorn-installation
- longhorn-csi-driver
- replicated-storage
- storageclass-creation

# PowerScale
- dell-powerscale-csi
- nfs-provisioner
- s3-access-configuration
- access-zone-setup
```

### Security Keywords

```yaml
# Host Security
- wazuh-agent-deployment
- cis-benchmark-hardening
- kernel-parameter-tuning
- rsyslog-configuration

# Cluster Security
- rbac-policies
- vault-integration
- keycloak-deployment
- cert-manager-setup

# Compliance
- nis2-compliance
- audit-logging
- security-scanning
```

### Monitoring Keywords

```yaml
# Observability
- prometheus-installation
- grafana-mimir-setup
- loki-deployment
- grafana-dashboards

# Integrations
- icinga-nrpe-agent
- ocs-inventory-agent
- alertmanager-configuration
```

### CI/CD Keywords

```yaml
# Pipeline
- gitlab-runner-registration
- harbor-deployment
- sonarqube-setup
- nexus-repository

# Security Scanning
- trivy-integration
- image-scanning
- vulnerability-management
```

### Operations Keywords

```yaml
# Lifecycle Management
- kured-deployment
- node-problem-detector
- automated-updates
- cluster-upgrade-procedures

# Backup & DR
- etcd-backup-automation
- velero-installation
- disaster-recovery-testing
```

### Integration Keywords

```yaml
# Active Directory
- ad-ldap-integration
- keycloak-federation
- sso-configuration

# External Systems
- active-directory-binding
- icinga-monitoring-integration
- central-syslog-forwarding
```

---

## ✅ CRITICAL SUCCESS FACTORS

### Pre-Deployment Phase

- [ ] **Network Validation**

  - RTT testing between all DCs (<5ms target)
  - Bandwidth testing (25GbE verification)
  - VLAN configuration validation
  - Firewall rule preparation

- [ ] **Hardware Preparation**

  - All servers racked and cabled
  - iDRAC configured and accessible
  - RAID arrays configured (OS + Data)
  - Firmware updates completed

- [ ] **Documentation**
  - Network diagram finalized
  - IP address allocation plan
  - VLAN assignments documented
  - DNS entries prepared

### Deployment Phase

- [ ] **Ansible Playbook Development**

  - OS hardening playbook tested
  - Kubernetes bootstrap playbook validated
  - Component deployment playbooks ready
  - Rollback procedures documented

- [ ] **Security Baseline**

  - CIS benchmark compliance from day 1
  - Wazuh agents deployed
  - Network policies defined
  - Vault initialized and sealed

- [ ] **Storage Configuration**
  - Longhorn deployed and validated
  - PowerScale Access Zones configured
  - StorageClasses created and tested
  - S3 buckets provisioned

### Post-Deployment Phase

- [ ] **Monitoring Setup**

  - Prometheus collecting metrics
  - Grafana dashboards configured
  - Loki ingesting logs
  - Icinga integration active
  - AlertManager rules configured

- [ ] **CI/CD Pipeline**

  - GitLab runners registered
  - Harbor operational
  - SonarQube integrated
  - Test deployment successful

- [ ] **Operations Readiness**
  - Runbooks created
  - On-call procedures defined
  - Backup verification completed
  - DR plan tested

### Ongoing Operations

- [ ] **Regular Testing**

  - Monthly DR drills
  - Quarterly capacity reviews
  - Security vulnerability scans
  - Performance benchmarking

- [ ] **Continuous Improvement**
  - Review monitoring alerts
  - Optimize resource utilization
  - Update documentation
  - Train operations team

---

## � RELATED DOCUMENTATION

### Internal Documents

| Document                               | Description                        | Location                  |
| -------------------------------------- | ---------------------------------- | ------------------------- |
| **Védelmi Intézkedések Katalógusa**    | Security requirements catalog      | Security SharePoint       |
| **Sérülékenységmenedzsment**           | Vulnerability management lifecycle | Security SharePoint       |
| **Wazuh Dokumentáció**                 | Wazuh SIEM documentation           | Operations SharePoint     |
| **K8s Platform hardver specifikációk** | Hardware specifications            | Infrastructure SharePoint |
| **K8s_üzemeltetés.docx**               | Kubernetes operations manual       | Operations SharePoint     |

### External References

| Resource                       | URL                                    |
| ------------------------------ | -------------------------------------- |
| **Kubernetes Documentation**   | https://kubernetes.io/docs/            |
| **Cilium Documentation**       | https://docs.cilium.io/                |
| **Longhorn Documentation**     | https://longhorn.io/docs/              |
| **Harbor Documentation**       | https://goharbor.io/docs/              |
| **Prometheus Documentation**   | https://prometheus.io/docs/            |
| **Grafana Loki Documentation** | https://grafana.com/docs/loki/         |
| **CIS Kubernetes Benchmark**   | https://www.cisecurity.org/            |
| **NIS2 Directive**             | https://digital-strategy.ec.europa.eu/ |

---

## � OPEN QUESTIONS & TODO

### Technical Questions

| #   | Question                                              | Owner        | Priority | Status      |
| --- | ----------------------------------------------------- | ------------ | -------- | ----------- |
| 1   | Policy enforcement engine selection (Kyverno vs OPA)? | DevOps Team  | High     | Open        |
| 2   | DRP document completion timeline?                     | Operations   | High     | In Progress |
| 3   | Backup strategy finalization?                         | Storage Team | High     | Open        |
| 4   | Second PowerScale procurement timeline?               | Procurement  | Medium   | Open        |
| 5   | DC-DC network RTT measurement results?                | Network Team | Critical | Open        |

### Action Items

- [ ] Complete network latency testing (DC-DC RTT validation)
- [ ] Finalize DRP documentation
- [ ] Complete backup/restore procedures
- [ ] Develop comprehensive runbooks
- [ ] Schedule team training sessions
- [ ] Conduct tabletop DR exercise
- [ ] Review and approve security policies
- [ ] Establish change management procedures

---

## � CONTACTS & ESCALATION

### Platform Teams

| Role             | Responsibility          | Escalation Level |
| ---------------- | ----------------------- | ---------------- |
| **Platform Ops** | Physical infrastructure | Level 1          |
| **Cluster Ops**  | Kubernetes platform     | Level 2          |
| **Network Team** | Network & firewall      | Level 1          |
| **Storage Team** | PowerScale & Longhorn   | Level 2          |
| **SecOps**       | Security & compliance   | Level 2          |
| **DevOps**       | CI/CD & GitOps          | Level 2          |

---

## � VERSION HISTORY

| Version | Date       | Author           | Changes                       |
| ------- | ---------- | ---------------- | ----------------------------- |
| 1.0     | 2025-09-24 | Original Team    | Initial version (for review)  |
| 1.1     | 2025-10-03 | Original Team    | Added Rack Plans              |
| 2.0     | 2025-11-11 | DevOps Architect | Deep analysis & Ansible focus |

---

**Document Classification:** Internal Use Only  
**Last Updated:** November 11, 2025  
**Next Review:** February 11, 2026

---

## � CONCLUSION

This is an **enterprise-grade, production-ready Kubernetes platform** designed with:

✅ **High Availability** - Multi-DC stretched cluster  
✅ **Security First** - Zero Trust + NIS2 compliance  
✅ **Scalability** - Room for growth  
✅ **Automation** - Infrastructure as Code (Ansible)  
✅ **Observability** - Complete monitoring stack  
✅ **DevSecOps** - Integrated CI/CD pipeline

**Ready for implementation with proper planning and execution!** �

---

_Generated by: Senior DevOps Engineer & IT Architect_  
_For: 2Connect Enterprise Kubernetes Platform_
