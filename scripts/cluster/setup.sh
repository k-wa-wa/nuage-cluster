#!/bin/bash
set -eu

(
    cd terraform \
    && tofu init -reconfigure -backend-config=env/cluster/backend.tfbackend \
    && tofu apply --auto-approve -var-file=env/cluster/terraform.tfvars
)

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
