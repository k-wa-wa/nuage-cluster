#!/bin/bash
set -eu

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v --forks 100 -i playbooks/vm/hosts.yml playbooks/vm/site-k8s.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v --forks 100 -i playbooks/k8s/hosts.yml playbooks/k8s/site.yml

sed -i.bk 's/nuage-cluster-endpoint/192\.168\.5\.50/g' playbooks/k8s/admin.conf
rm playbooks/k8s/admin.conf.bk
chmod 600 playbooks/k8s/admin.conf
