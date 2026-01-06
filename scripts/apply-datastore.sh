#!/bin/bash
set -eu

tofu -chdir=terraform/environments/dev-persistent apply --auto-approve

ANSIBLE_CONFIG=playbooks/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/data-store.yml
ANSIBLE_CONFIG=playbooks/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/postgres.yml
