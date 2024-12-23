#!/bin/sh
set -e

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site.yml

# VMが起動し終わるまで待つ（aptのlockを外すのも待つ必要がある）
sleep 60

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/k8s/hosts.yml playbooks/k8s/site.yml

chmod 600 playbooks/k8s/admin.conf
