#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/lm-server/hosts.yml playbooks/lm-server/site.yml
