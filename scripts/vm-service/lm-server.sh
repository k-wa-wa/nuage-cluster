#!/bin/sh

set -e

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site-lm-server.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/lm-server/hosts.yml playbooks/lm-server/site.yml
