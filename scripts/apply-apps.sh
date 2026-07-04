#!/bin/bash

set -e
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

#################### CNI ####################
kustomize build --enable-helm manifests/common | kubectl apply -f -

#################### namespace, argocd, secrets, ... ####################
kubectl create secret generic sops-age-key \
  --namespace argocd \
  --from-file=keys.txt=$HOME/.config/sops/age/argocd_key.txt

kubectl apply -k manifests/bootstrap/ --server-side
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

kubectl apply -f manifests/apps/
kubectl apply -f manifests/apps/pg-cluster/base/endpoint.yaml
