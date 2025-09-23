#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    playbooks/pve-on-pve/site-generate-hosts.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/pve-on-pve/hosts.yml playbooks/pve-on-pve/site-setup-nodes.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'

echo "クラスタ内のネットワークに切り替えてね"
read

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/pve-on-pve/hosts.yml playbooks/pve-on-pve/site-setup-cluster.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'
