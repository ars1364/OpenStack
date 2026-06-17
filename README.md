# OpenStack Infrastructure as Code

Terraform configurations and automation for deploying and managing OpenStack cloud infrastructure.

## Overview
Infrastructure-as-Code modules for OpenStack environments, developed from real-world experience managing OpenStack across multiple datacenters.

## Experience Context
- Deployed OpenStack across **7 datacenters** using Kolla-Ansible
- Managed **CEPH distributed storage** at petabyte scale (90+ nodes, 6 DCs)
- Achieved **35% RAM reduction** on CEPH clusters, saving $150K+ in hardware costs
- Reduced datacenter bandwidth costs by **65%** through traffic optimization

## Tech Stack
- Terraform (HCL)
- OpenStack APIs
- Kolla-Ansible
- CEPH Storage

## Structure
Infrastructure modules and configurations for OpenStack resource provisioning and management.

## Deployments

- [cloudinative-openstack](deployments/cloudinative-openstack/) — Kolla-Ansible 2026.1 (Galaxy) all-in-one on a nested-KVM VM (24 vCPU / 96 GB / 1 TB), full service set incl. Octavia, Designate, Magnum, Skyline. Patches + Dockerfile overlays + systemd units + post-deploy bootstrap script — reproducible from a fresh KVM host. Also documents the planned migration off the dead `k8s_fedora_coreos_v1` Magnum driver to `magnum-capi-helm`.

## Guides

- [Recovering a Kolla-Ansible Galera split-brain — and the /etc/hosts gotcha that caused it](docs/galera-split-brain-recovery.md) — full walkthrough of diagnosing and recovering a 3-controller Kolla 2025.1 cluster after Keystone went 503, including the cloud-init `manage_etc_hosts` failure mode that re-arms the same outage on every reboot.