# PROD Environment Kubernetes Deployment Checklist

## Overview

- **Environment**: PROD (Production)
- **Total Duration**: 25 days (accelerated via DEV learnings)
- **Critical Path**: 11.5 days
- **Team Size**: 3-4 engineers (2 senior, 1-2 mid-level)
- **Prerequisites**:
  - DEV environment validated and stable
  - All DEV lessons learned documented
  - PROD-specific approvals obtained

---

## Document Control

- **Version**: 2.0 (Restructured)
- **Status**: Ready for Deployment
- **Last Updated**: 2025-12-07
- **Approval Required**: Network, Security, Platform, Operations, Management

---

## CRITICAL PROD DIFFERENCES FROM DEV

### Hardening Requirements

| Aspect                   | DEV                  | PROD               | Rationale                      |
| ------------------------ | -------------------- | ------------------ | ------------------------------ |
| **Availability**         | Single-AZ acceptable | Multi-AZ mandatory | 99.9% SLA                      |
| **Control Plane**        | 3 nodes              | 5 nodes            | Survive 2-node failure         |
| **Worker Nodes**         | 5 nodes              | 10+ nodes          | Workload capacity + resilience |
| **Network Policies**     | Audit mode           | **Enforcing mode** | Zero-trust security            |
| **etcd Backups**         | Every 12 hours       | Every 6 hours      | RPO = 6 hours max              |
| **Backup Retention**     | 7 days               | 90 days            | Compliance requirement         |
| **PodDisruptionBudgets** | Optional             | **Mandatory**      | HA enforcement                 |
| **Certificate Validity** | 180 days             | 365 days           | Reduce rotation frequency      |
| **DR Testing**           | Optional             | **Mandatory**      | Must test before handoff       |
| **CIS Benchmark**        | Target: 70%          | Target: 90%        | Production compliance          |
| **Change Windows**       | Anytime              | Maintenance only   | Business impact                |
| **Rollback Time**        | 2 hours acceptable   | < 30 minutes       | SLA requirement                |

### Additional PROD-Only Tasks

1. **Multi-AZ Validation**: Control plane nodes distributed across availability zones
2. **Disaster Recovery Testing**: Full etcd restore, PV restore, node replacement
3. **Performance Baseline**: Load testing with 1000 pods, 10k RPS
4. **Backup Automation Testing**: Verify automated backups run without manual intervention
5. **Incident Response Drill**: Simulate node failure, verify auto-recovery
6. **Certificate Rotation Dry-Run**: Test cert-manager renewal before expiry
7. **RBAC Escalation Testing**: Verify emergency break-glass procedures
8. **Network Policy Penetration Test**: Attempt to bypass policies (should fail)
9. **Monitoring Alert Validation**: Trigger all critical alerts, verify PagerDuty/Slack integration
10. **Runbook Execution Test**: Operations team must execute all procedures successfully

---

## Changes From DEV Deployment

### Accelerations (25-30% faster)

- ✅ **Pre-tested configurations**: Copy from validated DEV setup
- ✅ **Ansible playbooks debugged**: No trial-and-error
- ✅ **Team experience**: Familiar with task sequence
- ✅ **Troubleshooting shortcuts**: Known issues already resolved

### Additional Validations (PROD-specific)

- ✅ **DR testing added**: Phase 12 includes full disaster recovery
- ✅ **Multi-AZ verification**: Control plane spread validation
- ✅ **Load testing**: Performance baseline under production load
- ✅ **Compliance audit**: CIS benchmark + RBAC audit
- ✅ **Change freeze procedures**: Document maintenance windows

---

## Phase 0: Pre-Flight Validation (4 hours)

**Purpose**: Validate production prerequisites with zero tolerance for failures  
**Risk Level**: LOW (read-only)  
**Dependencies**: DEV deployment complete and stable

### Task PROD-PRE-001: Network Connectivity Validation

- **Category**: Network
- **Duration**: 45 minutes
- **Dependencies**: None
- **Risk Level**: LOW

#### Description

Identical to DEV-PRE-001 but with PROD IP ranges and **zero tolerance** for failures.

#### Prerequisites

- [ ] PROD IP allocation spreadsheet approved by network architecture
- [ ] Firewall rules approved by security team
- [ ] Change request for PROD network modifications approved

#### Steps

1. **Ping Test All PROD Node IPs**

```bash
# Test all planned PROD IPs (more nodes than DEV)
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13 10.1.1.14 \
          10.1.1.20 10.1.1.21 10.1.1.22 10.1.1.23 10.1.1.24 \
          10.1.1.25 10.1.1.26 10.1.1.27 10.1.1.28 10.1.1.29; do
  echo "Testing $ip..."
  ping -c 3 $ip || { echo "CRITICAL FAIL: $ip unreachable"; exit 1; }
done
```

Expected: **100% success - any failure halts deployment**

2. **Latency Verification** (PROD-specific)

```bash
# PROD requires <2ms latency (stricter than DEV)
fping -C 10 -q 10.1.1.10 10.1.1.11 10.1.1.12 2>&1 | tail -n 3
```

Expected: Average latency < 2ms (SLA requirement)

#### Acceptance Criteria

- [ ] 100% of IPs reachable (no exceptions)
- [ ] Latency < 2ms for all local IPs (**stricter than DEV's 5ms**)
- [ ] Zero packet loss over 100 pings per node
- [ ] Network team written sign-off obtained

#### Rollback Procedure

N/A (read-only). **Any failure requires network team escalation and re-validation.**

#### Notes

- **PROD-Specific**: No tolerance for "mostly working" - must be perfect
- **Multi-AZ**: Validate cross-AZ latency (may be 5-10ms - document)

---

### Task PROD-PRE-006: Multi-AZ Control Plane Validation

- **Category**: Infrastructure
- **Duration**: 1 hour
- **Dependencies**: PROD-PRE-001
- **Risk Level**: HIGH

#### Description

**NEW PROD-ONLY TASK**: Verify that control plane nodes are distributed across multiple availability zones for HA.

#### Prerequisites

- [ ] AZ assignment documented (e.g., Master-01/02 in AZ-A, Master-03/04 in AZ-B, Master-05 in AZ-C)
- [ ] Cross-AZ network connectivity validated

#### Steps

1. **Verify Physical/Logical AZ Separation**

```bash
# Document which nodes are in which AZ
# Example: Check rack location, switch uplinks, power circuits
Node dev-k8s-master-01: AZ-A (Rack 1A, Switch 1)
Node dev-k8s-master-02: AZ-A (Rack 1B, Switch 1)
Node dev-k8s-master-03: AZ-B (Rack 2A, Switch 2)
Node dev-k8s-master-04: AZ-B (Rack 2B, Switch 2)
Node dev-k8s-master-05: AZ-C (Rack 3A, Switch 3)
```

2. **Cross-AZ Latency Test**

```bash
# Test latency between AZs (should be <10ms)
ping -c 100 10.1.1.10  # From AZ-A node
ping -c 100 10.1.1.12  # From AZ-B node (cross-AZ)
```

Expected: <10ms average, <50ms max

3. **AZ Failure Simulation** (on paper - not actual test)

```
Scenario 1: AZ-A fails (loses nodes 01, 02)
  - Remaining: 03, 04, 05 (3 of 5) - etcd quorum maintained ✓
  - Result: Cluster survives

Scenario 2: AZ-B fails (loses nodes 03, 04)
  - Remaining: 01, 02, 05 (3 of 5) - etcd quorum maintained ✓
  - Result: Cluster survives
```

#### Acceptance Criteria

- [ ] Control plane nodes confirmed in 2+ availability zones
- [ ] No single AZ contains quorum (3+ nodes)
- [ ] Cross-AZ latency acceptable (<10ms)
- [ ] AZ failure scenarios documented

#### Rollback Procedure

N/A (planning validation). If AZ distribution inadequate, re-plan node placement.

#### Notes

- **Quorum Math**: 5-node control plane tolerates 2 failures (3/5 quorum)
- **Best Practice**: 3 AZs with 2-2-1 distribution (2 in AZ-A, 2 in AZ-B, 1 in AZ-C)

---

### Phase 0 Smoke Test (PROD)

**PROD version includes additional checks:**

```bash
#!/bin/bash
echo "=== PROD Phase 0 Smoke Test (Zero Tolerance) ==="

FAIL=0

# Test 1: All nodes pingable with strict latency
for ip in 10.1.1.{10..29}; do
  ping -c 5 -W 1 $ip > /dev/null 2>&1 || { echo "FAIL: $ip not reachable"; FAIL=1; }
  latency=$(ping -c 10 $ip | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
  if (( $(echo "$latency > 2" | bc -l) )); then
    echo "FAIL: $ip latency ${latency}ms > 2ms threshold"
    FAIL=1
  fi
done

# Test 2: DNS resolution
nslookup prod-k8s-master-01.hansa.local > /dev/null 2>&1 || { echo "FAIL: DNS"; FAIL=1; }

# Test 3: LDAP bind with PROD service account
ldapsearch -x -H ldaps://ad.hansa.local:636 \
  -D "svc-k8s-prod-ldap@hansa.local" -w "$PROD_LDAP_PASS" \
  -b "DC=hansa,DC=local" "(objectClass=*)" -LLL > /dev/null 2>&1 || { echo "FAIL: LDAP"; FAIL=1; }

# Test 4: Multi-AZ validation (control plane spread)
# (Manual check - document results)
echo "Manual Check: Verify control plane AZ distribution documented"

if [ $FAIL -eq 1 ]; then
  echo "=== CRITICAL: Smoke Test FAILED - Deployment HALTED ==="
  exit 1
else
  echo "=== Smoke Test PASSED - Proceed to Phase 1 ==="
fi
```

**Gate**: **ZERO failures tolerated**. Any failure requires root cause analysis and re-validation.

---

## Phase 3: Kubernetes Core (2 days - accelerated)

**Purpose**: Production-grade HA Kubernetes cluster  
**Dependencies**: Phase 2 complete  
**Risk Level**: **CRITICAL**

### Task PROD-K8S-001: Control Plane Initialization (First Master)

- **Category**: Kubernetes Core
- **Duration**: 1 hour
- **Dependencies**: PROD-OS-002
- **Risk Level**: **CRITICAL**

#### Description

Initialize first control plane node with **production-grade configuration**. This is the most critical task - any errors cascade.

#### Prerequisites

- [ ] etcd backup strategy documented (even though cluster not yet running)
- [ ] kubeadm config file prepared with PROD settings
- [ ] Control plane VIP configured (kube-vip will manage later)
- [ ] **PROD-specific**: Change freeze window active (all other changes locked out)

#### Steps

1. **Create PROD kubeadm Config**

```yaml
# /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.5 # Latest stable
controlPlaneEndpoint: "prod-k8s-api.hansa.local:6443" # VIP
networking:
  podSubnet: "10.244.0.0/16" # Cilium
  serviceSubnet: "10.96.0.0/16"
etcdLocal:
  dataDir: "/var/lib/etcd"
  extraArgs:
    auto-compaction-retention: "3" # Compact every 3 hours
    snapshot-count: "10000"
    quota-backend-bytes: "8589934592" # 8GB (PROD size)
apiServer:
  extraArgs:
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-log-maxage: "90" # PROD retention
    audit-log-maxbackup: "10"
    audit-log-maxsize: "100"
    enable-admission-plugins: "NodeRestriction,PodSecurityPolicy" # PROD hardening
controllerManager:
  extraArgs:
    node-monitor-grace-period: "40s" # PROD: faster node failure detection
    pod-eviction-timeout: "30s" # PROD: faster pod rescheduling
```

2. **Initialize Control Plane**

```bash
# Take "pre-init" etcd backup (empty, but establishes process)
mkdir -p /var/backups/etcd
# (Backup will happen after init)

# Initialize
sudo kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs | tee /tmp/kubeadm-init.log
```

Expected output:

```
Your Kubernetes control-plane has initialized successfully!
[bootstrap-token] ... join --token ...
```

3. **IMMEDIATE: Install Cilium CNI** (within 5 minutes)

```bash
# CRITICAL: Must install CNI before nodes can reach Ready state
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}

# Install Cilium with PROD monitoring enabled
cilium install --version 1.14.5 \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true \
  --set hubble.enabled=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,icmp,http}"
```

Expected: `✅ Cilium was successfully installed!`

4. **First etcd Backup** (PROD-specific)

```bash
# Backup immediately after successful init
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
sudo ETCDCTL_API=3 etcdctl snapshot status /var/backups/etcd/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db --write-out=table
```

Expected: Backup shows healthy snapshot

5. **Verify Control Plane Health**

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

Expected:

- Node shows `Ready` status (after Cilium install)
- All kube-system pods `Running` (etcd, kube-apiserver, kube-controller-manager, kube-scheduler)

#### Acceptance Criteria

- [ ] kubeadm init completed successfully
- [ ] Cilium CNI installed within 5 minutes
- [ ] First node shows `Ready` status
- [ ] All kube-system pods healthy
- [ ] etcd backup created and verified
- [ ] Join token and cert key saved securely (for additional masters)
- [ ] **PROD**: Audit logging enabled and writing to /var/log/kubernetes/audit.log

#### Rollback Procedure

**CRITICAL ROLLBACK STEPS**:

```bash
# If init fails or cluster unstable

# 1. Reset node completely
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd /var/lib/kubelet
sudo rm -rf ~/.kube

# 2. Clean iptables rules
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# 3. Restart containerd
sudo systemctl restart containerd

# 4. Re-init with revised config
sudo kubeadm init --config /tmp/kubeadm-config-fixed.yaml --upload-certs
```

#### Notes

- **PROD-Specific**: Control plane VIP (prod-k8s-api.hansa.local) must resolve before init
- **Timing Critical**: CNI must be installed within 5 minutes or node stays NotReady
- **Security**: Save join tokens to secure vault immediately (not plain text)
- **Multi-Master**: Save certificate key for joining additional control plane nodes

---

### Task PROD-K8S-002: Additional Control Plane Joins (Nodes 2-5)

- **Category**: Kubernetes Core
- **Duration**: 2 hours (4 nodes, parallelizable)
- **Dependencies**: PROD-K8S-001
- **Risk Level**: **CRITICAL**

#### Description

Join 4 additional control plane nodes to establish HA quorum. **PROD requires 5 nodes** for 2-node failure tolerance.

#### Prerequisites

- [ ] First master healthy (PROD-K8S-001 complete)
- [ ] Join token and certificate key from PROD-K8S-001
- [ ] etcd backup from first master stored securely

#### Steps

1. **Prepare Join Command** (from first master output)

```bash
# Command will look like:
sudo kubeadm join prod-k8s-api.hansa.local:6443 --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:xxxxx \
  --control-plane --certificate-key yyyyy
```

2. **Join Nodes 2-5 Sequentially** (NOT parallel - etcd requires sequential joins)

```bash
# On prod-k8s-master-02:
sudo kubeadm join prod-k8s-api.hansa.local:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane --certificate-key <CERT-KEY> | tee /tmp/join-master-02.log

# Wait for node to reach Ready, then next node
# On prod-k8s-master-03:
sudo kubeadm join ... | tee /tmp/join-master-03.log

# Repeat for masters 04, 05
```

3. **Verify etcd Cluster Health After Each Join**

```bash
# From any master node:
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Expected: Shows all joined members, all healthy

4. **Backup etcd After Final Join**

```bash
# Full 5-node etcd backup
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/etcd-5node-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

#### Acceptance Criteria

- [ ] All 5 control plane nodes show `Ready` status
- [ ] etcd cluster has 5 healthy members
- [ ] Quorum achievable with any 3 nodes (tested via `etcdctl member list`)
- [ ] API server reachable from all master nodes
- [ ] etcd backup from 5-node cluster verified

#### Rollback Procedure

```bash
# If a master join fails:

# 1. Remove failed member from etcd cluster (from a healthy master)
sudo ETCDCTL_API=3 etcdctl member remove <MEMBER_ID> \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 2. Reset failed node
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/etcd

# 3. Re-join
sudo kubeadm join ... --control-plane --certificate-key ...
```

#### Notes

- **Join Order Matters**: Join masters sequentially, not parallel (etcd requirement)
- **PROD HA**: 5 masters survive 2-node failure (3/5 quorum)
- **Certificate Key Expiry**: Valid for 2 hours - re-upload if expired: `kubeadm init phase upload-certs --upload-certs`

---

## Phase 6: Security Infrastructure (2.5 days - accelerated)

**Purpose**: Production-hardened security stack  
**Dependencies**: Phase 5 complete  
**Risk Level**: **CRITICAL**

### Task PROD-SEC-008: Network Policy Enforcement (PROD-ONLY)

- **Category**: Security
- **Duration**: 3 hours
- **Dependencies**: PROD-NET-002 (network policies created)
- **Risk Level**: **HIGH**

#### Description

**NEW PROD-ONLY TASK**: Transition network policies from audit mode to **enforcing mode**. This blocks non-compliant traffic.

#### Prerequisites

- [ ] Network policies tested in DEV (audit mode logs reviewed)
- [ ] All legitimate traffic patterns documented
- [ ] Security team approval for enforcement
- [ ] Rollback procedure tested

#### Steps

1. **Review Audit Logs from DEV** (apply lessons learned)

```bash
# Check Cilium audit logs for denied traffic that should be allowed
kubectl logs -n kube-system -l k8s-app=cilium --tail=1000 | grep "Policy denied"
```

Expected: Zero unexpected denials

2. **Enable Enforcing Mode**

```bash
# Apply annotation to namespace to enforce policies
kubectl annotate namespace default "policy.cilium.io/enforcement=enabled" --overwrite
kubectl annotate namespace kube-system "policy.cilium.io/enforcement=enabled" --overwrite
# Repeat for all namespaces
```

3. **Validation Test - Attempt Policy Violation**

```bash
# Try to access pod from disallowed namespace (should fail)
kubectl run test-denied -n default --image=busybox --rm -it -- wget -O- http://prometheus-server.monitoring.svc.cluster.local:9090
```

Expected: **Connection timeout** (policy blocking works)

4. **Validation Test - Verify Allowed Traffic**

```bash
# DNS should still work (allowed by base policy)
kubectl run test-allowed -n default --image=busybox --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

Expected: **DNS resolution succeeds**

5. **Monitor for 24 Hours** (PROD-specific)

```bash
# Watch for unexpected blocked traffic
kubectl logs -n kube-system -l k8s-app=cilium -f | grep "Policy denied"
```

Expected: Zero unexpected denials (only known test traffic)

#### Acceptance Criteria

- [ ] Network policies in enforcing mode
- [ ] Test violation blocked successfully
- [ ] Legitimate traffic still flows (DNS, metrics, logs)
- [ ] 24-hour monitoring shows no unexpected blocks
- [ ] Grafana dashboard shows policy drops (expected test traffic only)

#### Rollback Procedure

**IMMEDIATE ROLLBACK IF PRODUCTION TRAFFIC BLOCKED**:

```bash
# Disable enforcement (back to audit mode)
kubectl annotate namespace default "policy.cilium.io/enforcement=audit" --overwrite
kubectl annotate namespace kube-system "policy.cilium.io/enforcement=audit" --overwrite

# Emergency: Disable all network policies
kubectl delete networkpolicy --all -A  # LAST RESORT
```

#### Notes

- **PROD-Only**: DEV stays in audit mode indefinitely
- **Gradual Rollout**: Enable enforcement per namespace, not all at once
- **Testing Window**: Do this during low-traffic period (weekend)
- **Monitoring**: Watch metrics closely for 24 hours after enforcement

---

## Phase 12: Validation & Handoff (1.5 days)

**Purpose**: Production readiness certification  
**Dependencies**: All phases complete  
**Risk Level**: MEDIUM

### Task PROD-VAL-001: Disaster Recovery Testing (PROD-ONLY)

- **Category**: Disaster Recovery
- **Duration**: 4 hours
- **Dependencies**: PROD-BACKUP-001
- **Risk Level**: HIGH (testing in production)

#### Description

**MANDATORY PROD TASK**: Validate that cluster can be recovered from catastrophic failure. Tests etcd restore, PV restore, and node replacement.

#### Prerequisites

- [ ] etcd snapshot available (< 6 hours old)
- [ ] PV backups available (Velero/Longhorn)
- [ ] DR runbook prepared
- [ ] Change window scheduled (off-hours)
- [ ] Stakeholders notified (testing may cause brief disruption)

#### Steps

**Test 1: etcd Restore Simulation**

```bash
# 1. Take final pre-test backup
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd/pre-dr-test.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 2. Create test namespace with data
kubectl create namespace dr-test
kubectl run dr-test-pod -n dr-test --image=nginx
kubectl wait --for=condition=ready pod/dr-test-pod -n dr-test --timeout=60s

# 3. Simulate data loss (delete namespace)
kubectl delete namespace dr-test

# 4. Restore from backup (CRITICAL STEP)
# Stop kubelet on all master nodes
sudo systemctl stop kubelet

# Restore etcd (on first master)
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/backups/etcd/pre-dr-test.db \
  --name=prod-k8s-master-01 \
  --initial-cluster="prod-k8s-master-01=https://10.1.1.10:2380,prod-k8s-master-02=https://10.1.1.11:2380" \
  --initial-cluster-token="etcd-prod-cluster" \
  --initial-advertise-peer-urls="https://10.1.1.10:2380" \
  --data-dir="/var/lib/etcd-restore"

# Move restored data
sudo rm -rf /var/lib/etcd.old
sudo mv /var/lib/etcd /var/lib/etcd.old
sudo mv /var/lib/etcd-restore /var/lib/etcd

# Restart kubelet
sudo systemctl start kubelet

# 5. Verify restoration
kubectl get namespace dr-test
kubectl get pod -n dr-test dr-test-pod
```

Expected: Namespace and pod restored

**Test 2: PV Restore Simulation**

```bash
# 1. Create test PVC with data
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dr-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
EOF

# Write test data
kubectl run dr-test-writer --image=busybox --restart=Never -- \
  sh -c "echo 'DR Test Data' > /data/test.txt" \
  --overrides='{"spec":{"containers":[{"name":"dr-test-writer","volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"dr-test-pvc"}}]}}'

# 2. Backup PVC (Velero)
velero backup create dr-test-backup --include-namespaces default --include-resources pvc,pv --wait

# 3. Delete PVC (simulate loss)
kubectl delete pvc dr-test-pvc

# 4. Restore from backup
velero restore create --from-backup dr-test-backup --wait

# 5. Verify data
kubectl run dr-test-reader --image=busybox --restart=Never --rm -it -- \
  cat /data/test.txt \
  --overrides='{"spec":{"containers":[{"name":"dr-test-reader","volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"dr-test-pvc"}}]}}'
```

Expected: Outputs "DR Test Data"

**Test 3: Node Failure Simulation**

```bash
# 1. Drain a worker node (simulate failure)
kubectl drain prod-k8s-worker-01 --ignore-daemonsets --delete-emptydir-data

# 2. Verify pods rescheduled
kubectl get pods -A -o wide | grep -v prod-k8s-worker-01
```

Expected: All pods moved to other nodes

# 3. Bring node back

kubectl uncordon prod-k8s-worker-01

````

#### Acceptance Criteria
- [ ] etcd restore successful (namespace + pod recovered)
- [ ] PV restore successful (data intact)
- [ ] Node drain/uncordon successful (pods rescheduled)
- [ ] No data loss during DR procedures
- [ ] Recovery time < 30 minutes (SLA requirement)
- [ ] DR runbook validated (all steps work as documented)

#### Rollback Procedure
```bash
# If DR test breaks production:
# 1. Restore from pre-test backup
sudo ETCDCTL_API=3 etcdctl snapshot restore /var/backups/etcd/pre-dr-test.db ...
# 2. Restart all master nodes
sudo systemctl restart kubelet
````

#### Notes

- **PROD-Only**: DR testing not required in DEV
- **Timing**: Perform during maintenance window (off-hours)
- **Communication**: Notify stakeholders before test (may see brief disruptions)
- **Documentation**: Update DR runbook with actual recovery times

---

## PROD-Specific Risk Matrix

| Task                       | DEV Risk | PROD Risk     | Additional Mitigation                       |
| -------------------------- | -------- | ------------- | ------------------------------------------- |
| Control Plane Init         | CRITICAL | **CRITICAL+** | Multi-AZ placement, immediate backup        |
| Network Policy Enforcement | N/A      | **HIGH**      | Gradual rollout, 24h monitoring             |
| DR Testing                 | N/A      | **HIGH**      | Off-hours testing, stakeholder notification |
| Certificate Rotation       | MEDIUM   | **HIGH**      | Dry-run in DEV first, rollback ready        |
| RBAC Changes               | HIGH     | **CRITICAL**  | Change freeze, break-glass procedure tested |
| Backup Automation          | MEDIUM   | **CRITICAL**  | Daily validation, off-cluster storage       |
| Load Testing               | LOW      | **MEDIUM**    | Production-like load, performance baseline  |
| Monitoring Alerts          | MEDIUM   | **HIGH**      | Alert fatigue prevention, escalation tested |

---

## PROD Acceptance Criteria (Final Gate)

### Technical Acceptance

- [ ] All 12 phases completed successfully
- [ ] CIS Kubernetes benchmark score ≥ 90%
- [ ] Network policies in enforcing mode
- [ ] DR procedures tested and documented
- [ ] Multi-AZ control plane validated
- [ ] Backup automation verified (6-hour RPO)
- [ ] Load testing passed (1000 pods, 10k RPS)
- [ ] Certificate expiry > 365 days

### Security Acceptance

- [ ] RBAC audit completed (least privilege verified)
- [ ] Network policy penetration test passed
- [ ] No default passwords or credentials
- [ ] Secrets encrypted at rest in etcd
- [ ] Audit logging enabled and retention verified (90 days)
- [ ] PodSecurityPolicies/Standards enforced

### Operational Acceptance

- [ ] Runbook complete and tested by operations team
- [ ] Monitoring alerts configured and validated
- [ ] PagerDuty/Slack integrations tested
- [ ] Incident response drill completed
- [ ] Change freeze procedures documented
- [ ] Escalation contacts confirmed

### Business Acceptance

- [ ] SLA targets defined (99.9% uptime)
- [ ] Maintenance windows scheduled
- [ ] Stakeholder sign-offs obtained
- [ ] First 3 production applications deployed successfully
- [ ] Performance meets baseline requirements

---

## PROD Handoff Checklist

### Documentation Delivered

- [ ] PROD deployment runbook (this document)
- [ ] DR recovery procedures
- [ ] RBAC management guide
- [ ] Certificate renewal procedures
- [ ] Backup/restore procedures
- [ ] Troubleshooting guide
- [ ] Architecture diagrams (network, security, storage)
- [ ] Change management procedures

### Training Completed

- [ ] Operations team trained (2-hour hands-on)
- [ ] DR drill completed with ops team
- [ ] Break-glass procedures demonstrated
- [ ] Monitoring dashboard walkthrough
- [ ] Escalation procedures reviewed

### Ongoing Responsibilities Transferred

- [ ] Daily backup verification (automated)
- [ ] Weekly DR test schedule (automated)
- [ ] Monthly CIS benchmark audit
- [ ] Quarterly certificate renewal review
- [ ] On-call rotation established

---

## Summary Timeline (PROD)

| Phase             | Duration | Notes                       |
| ----------------- | -------- | --------------------------- |
| 0 - Pre-Flight    | 4 hours  | Zero tolerance for failures |
| 1 - Network       | 2 days   | Pre-validated in DEV        |
| 2A - OS Install   | 1.5 days | Automated playbooks         |
| 2B - Monitoring   | 0.5 days | Known configuration         |
| 3 - K8s Core      | 2 days   | 5-node control plane        |
| 4 - Storage       | 1 day    | Copy DEV config             |
| 5 - Networking    | 1 day    | Enforce network policies    |
| 6 - Security      | 2.5 days | PROD-hardened               |
| 7 - Monitoring    | 2 days   | 90-day retention            |
| 8 - CI/CD         | 2 days   | Replicate DEV setup         |
| 9 - Platform      | 1 day    | Minimal testing             |
| 10 - Integrations | 1 day    | Known working               |
| 11 - Ansible      | 2 days   | Tested playbooks            |
| 12 - Validation   | 1.5 days | DR testing added            |

**Total**: ~25 days (30% faster than DEV due to learnings)

---

**Document Status**: Production Ready  
**Critical Path**: 11.5 days  
**Next Steps**: Final stakeholder approval, schedule maintenance windows  
**Handoff Target**: Day 25
