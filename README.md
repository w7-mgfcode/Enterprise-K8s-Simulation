# Enterprise K8s Simulation

A local Kubernetes simulation environment using Kind (Kubernetes in Docker) with enterprise-grade configurations.

## Overview

This project provides an automated setup for a local Kubernetes cluster simulating an enterprise environment with:
- **1 Control Plane** node
- **3 Worker** nodes labeled with `topology.kubernetes.io/zone=dc10-kozma`
- **Cilium CNI** for advanced networking
- **Mock Storage Classes** (`powerscale-nfs-prod` and `longhorn`)

## Quick Start

### Prerequisites

- Linux-based system (tested on Ubuntu)
- Docker installed and running
- At least 8GB RAM
- At least 20GB free disk space

### Setup

1. Clone the repository:
```bash
git clone https://github.com/w7-mgfcode/Enterprise-K8s-Simulation.git
cd Enterprise-K8s-Simulation
```

2. Run the setup script:
```bash
chmod +x setup-simulation.sh
./setup-simulation.sh
```

The script will:
- Install Kind, kubectl, and Helm (if not already installed)
- Create a Kind cluster with the specified configuration
- Install Cilium CNI via Helm
- Create mock StorageClasses

3. Verify the setup:
```bash
kubectl get nodes
kubectl get storageclass
kubectl get pods -A
```

## Project Structure

```
.
├── setup-simulation.sh          # Main setup script
├── kind-config.yaml             # Kind cluster configuration
├── .github/
│   └── workflows/
│       └── simulation-setup.yml # GitHub Actions workflow
├── docs/                        # Documentation
│   ├── README.md
│   ├── architecture.md
│   ├── setup-guide.md
│   └── troubleshooting.md
└── ansible/                     # Ansible automation (skeleton)
    ├── playbooks/
    ├── roles/
    ├── inventory/
    ├── group_vars/
    ├── host_vars/
    ├── ansible.cfg
    └── requirements.yml
```

## Configuration

### Kind Cluster

The cluster configuration is defined in `kind-config.yaml`:
- CNI: Disabled (Cilium installed separately)
- Pod Subnet: `10.244.0.0/16`
- Nodes: 1 control-plane + 3 workers with `dc10-kozma` zone labels

### Storage Classes

Two mock StorageClasses are created:
- **powerscale-nfs-prod**: No provisioner, WaitForFirstConsumer binding, Retain reclaim policy
- **longhorn**: No provisioner (mock), WaitForFirstConsumer binding, Delete reclaim policy

### Cilium CNI

Cilium is installed with the following features:
- Node initialization enabled
- Partial kube-proxy replacement
- External IPs and NodePort support
- Kubernetes IPAM mode

## CI/CD

GitHub Actions workflow automatically:
1. Sets up the cluster
2. Runs smoke tests to verify:
   - Correct node count (4 total)
   - 1 control-plane node
   - 3 worker nodes with proper labels
   - All nodes in Ready state
   - StorageClasses are created
   - Cilium pods are running

## Cleanup

To delete the cluster:
```bash
kind delete cluster --name enterprise-k8s
```

## Documentation

For detailed documentation, see the [docs/](./docs/) directory:
- [Architecture](./docs/architecture.md)
- [Setup Guide](./docs/setup-guide.md)
- [Troubleshooting](./docs/troubleshooting.md)

## Contributing

Contributions are welcome! Please ensure:
1. All scripts are tested
2. Documentation is updated
3. CI/CD pipeline passes

## License

This project is for simulation and testing purposes.