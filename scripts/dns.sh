#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site-dns.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/dns/hosts.yml playbooks/dns/site.yml
