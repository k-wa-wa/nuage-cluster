#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    playbooks/vpc/site-generate-hosts.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/vpc/hosts.yml playbooks/vpc/site-setup-vpc.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'

echo "クラスター内のネットワークに切り替えてから、クラスターをセットアップする"
echo "
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10' \
    playbooks/pve-cluster/site.yml \
    -i playbooks/pve-cluster/hosts-pve-xxx.yml
"
