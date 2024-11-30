#!/bin/sh

set -e
source .env

#################### helm chat更新 ####################
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

#################### metalLB ####################
./k apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
./k wait -n metallb-system \
  --for=condition=available \
  --timeout=300s \
  --all deployment
./k apply -f manifests/metallb.yaml

#################### ingress ####################
# ./k apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/cloud/deploy.yaml
# ./k wait --namespace ingress-nginx \
#   --for=condition=ready pod \
#   --selector=app.kubernetes.io/component=controller \
#   --timeout=120s
# ./k apply -f manifests/ingress.yaml

#################### postgres operator ####################
helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator
helm upgrade --install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui
helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=$NFS_SERVER_IP \
    --set nfs.path=/nfs
./k patch storageclass nfs-client -p '{"metadata": {"annotations": {"storageclass.beta.kubernetes.io/is-default-class": "true"}}}'
./k apply -f manifests/postgres.yaml

#################### 監視 ####################
./k get namespace ops 2>/dev/null || ./k create namespace ops
helm upgrade --install --namespace ops prometheus-grafana prometheus-community/kube-prometheus-stack -f manifests/ops/grafana-custom.yml
helm upgrade --install --namespace ops loki grafana/loki-stack -f manifests/ops/loki-custom.yaml
helm upgrade --install --namespace ops promtail grafana/promtail -f manifests/ops/promtail-custom.yaml

#################### apps ####################
./k apply -f manifests/pechka
