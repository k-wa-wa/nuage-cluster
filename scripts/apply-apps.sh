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

#################### infra ####################
./k apply -f manifests/infra/pvs/ # TODO: argocdでの管理を検討
./k apply -f manifests/infra/ingress/

#################### argocd ####################
./k apply -f manifests/argocd/apps/

#################### apps: dashboard ####################
./k apply -f manifests/dashboard-v2

#################### apps: pechka ####################
# ./k scale -n pechka deployment file-server-api --replicas=2
# ./k scale -n pechka deployment file-server-ui --replicas=2
