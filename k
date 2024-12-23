#!/bin/sh

kubectl --kubeconfig ./playbooks/k8s/admin.conf "$@"
