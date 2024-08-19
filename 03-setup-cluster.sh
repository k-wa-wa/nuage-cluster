#!/bin/sh
set -e

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/hosts.yml playbooks/site.yml
