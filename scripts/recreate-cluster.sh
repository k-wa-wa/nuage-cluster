#!/bin/bash
set -eu

ANSIBLE_CONFIG=playbooks-new/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/k8s.yml
