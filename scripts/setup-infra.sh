#!/bin/bash
set -eu

(
    cd terraform/environments/standalone \
    && tofu apply --auto-approve
)
(
    cd terraform/environments/cluster \
    && tofu apply --auto-approve
)

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/vm-common/hosts-standalone.yml playbooks/vm-common/site-standalone.yml \
    --ssh-extra-args='-o ConnectionAttempts=30 -o ConnectTimeout=10'

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/dns/hosts.yml playbooks/dns/site.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -v -i playbooks/proxy/hosts.yml playbooks/proxy/site.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/k8s/hosts.yml \
    playbooks/k8s/site-init-nodes.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/k8s/hosts.yml \
    playbooks/k8s/site-setup-loadbalancer.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    -i playbooks/k8s/hosts.yml \
    playbooks/k8s/site-init-control-plane.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    --limit "control-plane[0]" \
    -i playbooks/k8s/hosts.yml \
    playbooks/k8s/site-get-join-command.yml

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -v \
    --limit "control-plane[1:],worker-node" \
    -i playbooks/k8s/hosts.yml \
    playbooks/k8s/site-join-nodes.yml
