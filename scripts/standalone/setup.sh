#!/bin/bash
set -eu

(
    cd terraform/environments/standalone \
    && tofu apply --auto-approve
)

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm-common/hosts-standalone.yml playbooks/vm-common/site-standalone.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/dns/hosts.yml playbooks/dns/site.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/proxy/hosts.yml playbooks/proxy/site.yml
