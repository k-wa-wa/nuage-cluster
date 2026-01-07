#!/bin/bash

set -e
export KUBECONFIG=playbooks/admin.conf

#################### namespace, argocd, secrets, ... ####################
./k apply -k manifests/bootstrap/
./k wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s
./k wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

./k apply -f manifests/
./k apply -f manifests/apps/pg-cluster/base/endpoint.yaml

# TODO:
# - istio-ingressgateway の作成タイミングによって、ErrImgPullBackOff になる。rollout で解消するが、要調査

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
