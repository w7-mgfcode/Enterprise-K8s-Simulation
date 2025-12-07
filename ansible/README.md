# Ansible Automation

This directory contains Ansible playbooks and roles for automating the Enterprise K8s Simulation environment.

## Directory Structure

```
ansible/
├── playbooks/       # Ansible playbooks
├── roles/           # Custom Ansible roles
├── inventory/       # Inventory files
├── group_vars/      # Group variables
├── host_vars/       # Host-specific variables
└── ansible.cfg      # Ansible configuration
```

## Usage

> **Note:** Playbooks and roles will be added as the project evolves.

### Running Playbooks

```bash
ansible-playbook -i inventory/hosts playbooks/example.yml
```

## Requirements

Install required Ansible collections:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Development

When creating new roles or playbooks, follow Ansible best practices and maintain consistency with the existing structure.
