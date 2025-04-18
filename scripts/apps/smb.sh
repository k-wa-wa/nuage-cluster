#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/smb/hosts.yml playbooks/smb/site.yml
