#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/nfs/hosts.yml playbooks/nfs/site.yml
