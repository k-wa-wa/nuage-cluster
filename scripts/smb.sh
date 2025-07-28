#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site-smb.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/smb/hosts.yml playbooks/smb/site.yml

