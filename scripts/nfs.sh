#!/bin/sh

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site-nfs.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/nfs/hosts.yml playbooks/nfs/site.yml
