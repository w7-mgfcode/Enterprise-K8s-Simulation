#!/bin/bash
set -e

echo "======================================"
echo "Enterprise K8s Simulation Setup"
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Versions
KIND_VERSION=${KIND_VERSION:-"v0.20.0"}
HELM_VERSION=${HELM_VERSION:-"v3.13.0"}
KUBECTL_VERSION=${KUBECTL_VERSION:-"v1.28.0"}
CILIUM_VERSION=${CILIUM_VERSION:-"1.14.3"}

echo -e "${YELLOW}Step 1: Installing prerequisites...${NC}"

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${YELLOW}Warning: This script is optimized for Linux. Detected OS: $OSTYPE${NC}"
fi

# Install Kind
if ! command -v kind &> /dev/null; then
    echo "Installing Kind ${KIND_VERSION}..."
    curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-$(uname)-amd64"
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo -e "${GREEN}Kind installed successfully${NC}"
else
    echo -e "${GREEN}Kind already installed: $(kind version)${NC}"
fi

# Install Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing Kubectl ${KUBECTL_VERSION}..."
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
    echo -e "${GREEN}Kubectl installed successfully${NC}"
else
    echo -e "${GREEN}Kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)${NC}"
fi

# Install Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm ${HELM_VERSION}..."
    curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm.tar.gz
    tar -zxvf helm.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64 helm.tar.gz
    echo -e "${GREEN}Helm installed successfully${NC}"
else
    echo -e "${GREEN}Helm already installed: $(helm version --short)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 2: Creating Kind cluster...${NC}"

# Delete existing cluster if it exists
if kind get clusters 2>/dev/null | grep -q "^enterprise-k8s$"; then
    echo "Deleting existing cluster..."
    kind delete cluster --name enterprise-k8s
fi

# Create Kind cluster with config
echo "Creating Kind cluster with 1 control-plane and 3 worker nodes..."
kind create cluster --name enterprise-k8s --config kind-config.yaml

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s 2>/dev/null || true

echo ""
echo -e "${YELLOW}Step 3: Installing Cilium CNI via Helm...${NC}"

# Add Cilium Helm repository
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium
echo "Installing Cilium ${CILIUM_VERSION}..."
helm install cilium cilium/cilium \
    --version ${CILIUM_VERSION} \
    --namespace kube-system \
    --set nodeinit.enabled=true \
    --set kubeProxyReplacement=partial \
    --set hostServices.enabled=false \
    --set externalIPs.enabled=true \
    --set nodePort.enabled=true \
    --set hostPort.enabled=true \
    --set bpf.masquerade=false \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes

echo "Waiting for Cilium to be ready..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s 2>/dev/null || true

# Give Cilium more time to stabilize
sleep 10

echo ""
echo -e "${YELLOW}Step 4: Creating StorageClasses...${NC}"

# Create powerscale-nfs-prod StorageClass
echo "Creating powerscale-nfs-prod StorageClass..."
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: powerscale-nfs-prod
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF

# Create longhorn StorageClass (using local-path provisioner)
echo "Creating longhorn StorageClass..."
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF

echo ""
echo -e "${GREEN}======================================"
echo "Setup Complete!"
echo "======================================${NC}"
echo ""
echo "Cluster Info:"
kubectl cluster-info
echo ""
echo "Nodes:"
kubectl get nodes -o wide
echo ""
echo "StorageClasses:"
kubectl get storageclass
echo ""
echo "Cilium Status:"
kubectl get pods -n kube-system -l k8s-app=cilium
echo ""
echo -e "${GREEN}You can now interact with your cluster using kubectl!${NC}"
