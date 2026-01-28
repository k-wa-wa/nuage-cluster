#!/bin/bash

set -e
export KUBECONFIG=playbooks/admin.conf

#################### namespace, argocd, secrets, ... ####################
cp .ssh/id_ed25519 manifests/bootstrap/secrets/id_ed25519_for_devops_server
./k apply -k manifests/bootstrap/
./k wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s
./k wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

./k apply -f manifests/apps/
./k apply -f manifests/apps/pg-cluster/base/endpoint.yaml

#################### infra #################### TODO: argocdでの管理を検討
./k apply -f manifests/infra/pvs/

#################### apps: pechka ####################
# ./k scale -n pechka deployment file-server-api --replicas=2
# ./k scale -n pechka deployment file-server-ui --replicas=2

####################
# 以下は monitoring-stack にまとめる想定のため、今はこのままとする
####################
./k apply -f manifests/argocd/apps/
./k apply -f manifests/dashboard-v2

# istio-ingressgateway の作成タイミングによって、ErrImgPullBackOff になるため、rollout で対応する
if ! ./k wait --for=condition=Available --timeout=60s -n istio-system deployment/istio-ingressgateway 2>/dev/null; then
  if ./k get pods -n istio-system -l app=istio-ingressgateway | grep -E "ErrImagePull|ImagePullBackOff"; then
    ./k rollout restart -n istio-system deployment/istio-ingressgateway
  fi
fi
