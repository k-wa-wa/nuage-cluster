#!/bin/bash
set -eu

tofu -chdir=terraform/environments/dev apply --auto-approve

ANSIBLE_CONFIG=playbooks/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/dns.yml
ANSIBLE_CONFIG=playbooks/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/proxy.yml
ANSIBLE_CONFIG=playbooks/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/omada-controller.yml
