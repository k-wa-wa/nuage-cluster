#!/bin/sh
set -e

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/vm/hosts.yml playbooks/vm/site-k8s.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/k8s/hosts.yml playbooks/k8s/site.yml

cp playbooks/k8s/admin.conf playbooks/k8s/admin.conf.cp
sed 's/nuage-cluster-endpoint/192\.168\.5\.50/g' playbooks/k8s/admin.conf.cp > playbooks/k8s/admin.conf
rm playbooks/k8s/admin.conf.cp

chmod 600 playbooks/k8s/admin.conf
