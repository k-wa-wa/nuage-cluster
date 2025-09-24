#!/bin/bash
set -eu

(
    cd terraform/environments/persistent \
    && tofu apply --auto-approve
)

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/nfs/hosts.yml playbooks/nfs/site.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'
