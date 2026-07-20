#!/bin/bash

set -e
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

#################### namespace, CNI, argocd, secrets, ... ####################
kustomize build --enable-helm manifests/bootstrap | kubectl apply --server-side -f -
kubectl create secret generic sops-age-key \
  --namespace argocd \
  --from-file=keys.txt=$HOME/.config/sops/age/argocd_key.txt \
  --dry-run=client -o yaml | kubectl apply -f -

# CRDの確立を待つ
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s
kubectl wait --for=condition=Established crd/applicationsets.argoproj.io --timeout=60s
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

kubectl apply -f manifests/apps/
