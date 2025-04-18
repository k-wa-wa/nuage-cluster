#!/bin/bash
set -e

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v --forks 100 -i playbooks/vm/hosts.yml playbooks/vm/site-k8s.yml
