#!/usr/bin/env bash
set -euo pipefail

# terragrunt import commands to recover state for hosts configuration

echo "Importing Linux Bridges..."
terragrunt import proxmox_network_linux_bridge.dummy_nuc1 nuc-1/dummy
terragrunt import proxmox_network_linux_bridge.dummy_nuc2 nuc-2/dummy
terragrunt import proxmox_network_linux_bridge.dummy_server1 server-1/dummy

terragrunt import proxmox_network_linux_bridge.vmbr1_server_1 server-1/vmbr1
terragrunt import proxmox_network_linux_bridge.vmbr999_server_1 server-1/vmbr999

terragrunt import proxmox_network_linux_bridge.vmbr0_nuc1 nuc-1/vmbr0
terragrunt import proxmox_network_linux_bridge.vmbr0_nuc2 nuc-2/vmbr0
terragrunt import proxmox_network_linux_bridge.vmbr0_server1 server-1/vmbr0
terragrunt import proxmox_network_linux_bridge.vmbr10_nuc1 nuc-1/vmbr10
terragrunt import proxmox_network_linux_bridge.vmbr10_nuc2 nuc-2/vmbr10
terragrunt import proxmox_network_linux_bridge.vmbr10_server1 server-1/vmbr10
terragrunt import proxmox_network_linux_bridge.vmbr11_nuc1 nuc-1/vmbr11
terragrunt import proxmox_network_linux_bridge.vmbr11_nuc2 nuc-2/vmbr11
terragrunt import proxmox_network_linux_bridge.vmbr11_server1 server-1/vmbr11

echo "Importing Linux VLANs..."
terragrunt import proxmox_network_linux_vlan.vmbr10_1_nuc1 nuc-1:vmbr10.1
terragrunt import proxmox_network_linux_vlan.vmbr10_1_nuc2 nuc-2:vmbr10.1
terragrunt import proxmox_network_linux_vlan.vmbr10_2_nuc2 nuc-2:vmbr10.2
terragrunt import proxmox_network_linux_vlan.vmbr10_2_server1 server-1:vmbr10.2
terragrunt import proxmox_network_linux_vlan.vmbr10_3_server1 server-1:vmbr10.3
terragrunt import proxmox_network_linux_vlan.vmbr10_3_nuc1 nuc-1:vmbr10.3

echo "Importing Download Files..."
terragrunt import 'proxmox_download_file.talos_iscsi_image["nuc-1"]' nuc-1/local/iso/talos-iscsi.iso
terragrunt import 'proxmox_download_file.talos_iscsi_image["nuc-2"]' nuc-2/local/iso/talos-iscsi.iso
terragrunt import 'proxmox_download_file.talos_iscsi_image["server-1"]' server-1/local/iso/talos-iscsi.iso

terragrunt import 'proxmox_download_file.lxc_ubuntu_2504["nuc-1"]' nuc-1/local/vztmpl/ubuntu-25.04-server-cloudimg-amd64-root.tar.xz
terragrunt import 'proxmox_download_file.lxc_ubuntu_2504["nuc-2"]' nuc-2/local/vztmpl/ubuntu-25.04-server-cloudimg-amd64-root.tar.xz
terragrunt import 'proxmox_download_file.lxc_ubuntu_2504["server-1"]' server-1/local/vztmpl/ubuntu-25.04-server-cloudimg-amd64-root.tar.xz

terragrunt import 'proxmox_download_file.lxc_ubuntu_2404["nuc-1"]' nuc-1/local/vztmpl/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz
terragrunt import 'proxmox_download_file.lxc_ubuntu_2404["nuc-2"]' nuc-2/local/vztmpl/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz
terragrunt import 'proxmox_download_file.lxc_ubuntu_2404["server-1"]' server-1/local/vztmpl/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz

terragrunt import 'proxmox_download_file.nixos_base_lxc["nuc-1"]' nuc-1/local/vztmpl/nixos-base-lxc.tar.xz
terragrunt import 'proxmox_download_file.nixos_base_lxc["nuc-2"]' nuc-2/local/vztmpl/nixos-base-lxc.tar.xz
terragrunt import 'proxmox_download_file.nixos_base_lxc["server-1"]' server-1/local/vztmpl/nixos-base-lxc.tar.xz

terragrunt import 'proxmox_download_file.nixos_base_vm["nuc-1"]' nuc-1/local/iso/nixos-base-vm.iso
terragrunt import 'proxmox_download_file.nixos_base_vm["nuc-2"]' nuc-2/local/iso/nixos-base-vm.iso
terragrunt import 'proxmox_download_file.nixos_base_vm["server-1"]' server-1/local/iso/nixos-base-vm.iso

echo "Importing SDN resources..."
terragrunt import proxmox_sdn_fabric_ospf.main main
terragrunt import proxmox_sdn_fabric_node_ospf.main_nuc1 main/nuc-1
terragrunt import proxmox_sdn_fabric_node_ospf.main_nuc2 main/nuc-2
terragrunt import proxmox_sdn_fabric_node_ospf.main_server1 main/server-1

# Note: proxmox_sdn_applier requires a unix timestamp in milliseconds as a placeholder ID.
# Since it is a trigger-only resource, you might need to determine the actual ID if needed,
# or apply it cleanly. Here is the placeholder command:
# terragrunt import proxmox_sdn_applier.example_applier <unix_timestamp_ms>
# terragrunt import proxmox_sdn_applier.finalizer <unix_timestamp_ms>
