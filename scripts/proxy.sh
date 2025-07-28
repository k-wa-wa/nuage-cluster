#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site-proxy.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/proxy/hosts.yml playbooks/proxy/site.yml
