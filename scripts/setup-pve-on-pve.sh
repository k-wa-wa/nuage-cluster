#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/bastion/hosts.yml playbooks/bastion/site.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/pve-on-pve/hosts.yml playbooks/pve-on-pve/site-setup-nodes.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'

sleep 15

rm -rf ~/.ssh/known_hosts
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/pve-on-pve/hosts.yml playbooks/pve-on-pve/site-setup-cluster.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'
