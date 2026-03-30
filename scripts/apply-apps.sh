#!/bin/bash

set -e
export KUBECONFIG=./terraform/vpc/zone-private/kubeconfig-private

#################### CNI ####################
kustomize build --enable-helm manifests/common | kubectl apply -f -

#################### namespace, argocd, secrets, ... ####################
cp .ssh/id_ed25519 manifests/bootstrap/secrets/id_ed25519_for_devops_server
kubectl apply -k manifests/bootstrap/ --server-side
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

kubectl apply -f manifests/apps/
kubectl apply -f manifests/apps/pg-cluster/base/endpoint.yaml
