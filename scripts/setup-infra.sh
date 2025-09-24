#!/bin/bash
set -eu

(
    cd terraform/targets/standalone \
    && tofu apply --auto-approve
)
(
    cd terraform/targets/cluster \
    && tofu apply --auto-approve
)

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/vm-common/hosts-standalone.yml playbooks/vm-common/site-standalone.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/dns/hosts.yml playbooks/dns/site.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/proxy/hosts.yml playbooks/proxy/site.yml
