#!/bin/sh

set -e

# metalLB
./k apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
./k apply -f manifests/metallb.yaml

# ingress
./k apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
./k apply -f manifests/ingress.yaml

# ./k get validatingwebhookconfigurations  --all-namespaces
# ./k delete validatingwebhookconfigurations ingress-nginx-admission

# apps
./k apply -f manifests/pechka
