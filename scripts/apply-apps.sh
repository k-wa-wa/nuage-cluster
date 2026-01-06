#!/bin/bash

set -e
export KUBECONFIG=playbooks/admin.conf

#################### namespace, argocd, secrets, ... ####################
./k apply -k manifests/bootstrap/
./k apply -f manifests/apps/pg-cluster/base/endpoint.yaml

#################### istio ####################
if ! ./k get ns istio-system &> /dev/null; then
  ./istio-1.26.2/bin/istioctl install -y -f istio-1.26.2/istio-custom.yaml
fi
./k apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.0/cert-manager.yaml
./k apply -f istio-1.26.2/samples/addons

#################### argocd ####################
./k apply -f manifests/argocd/apps/

#################### apps: dashboard ####################
./k apply -f manifests/dashboard-v2

#################### apps: pechka ####################
# argo workflow
curl -L https://github.com/argoproj/argo-workflows/releases/download/v3.6.2/quick-start-minimal.yaml \
  | sed 's/namespace: argo/namespace: pechka/g' \
  | ./k apply -n pechka -f -

# apps
./k apply -n pechka -f manifests/pechka
./k apply -f manifests/pechka/file-server
./k apply -f manifests/pechka/file-server-workflow

# ./k scale -n pechka deployment file-server-api --replicas=2
# ./k scale -n pechka deployment file-server-ui --replicas=2
