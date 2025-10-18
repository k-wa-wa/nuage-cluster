#!/bin/bash
set -eu

ANSIBLE_CONFIG=playbooks/ansible.cfg ansible-playbook -i playbooks/inventory/dev/hosts.yml playbooks/k8s.yml
