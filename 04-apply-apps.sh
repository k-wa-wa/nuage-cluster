#!/bin/sh

set -e
export KUBECONFIG=./playbooks/admin.conf

#################### helm chat更新 ####################
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
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

#################### 監視 ####################
./k get namespace ops 2>/dev/null || ./k create namespace ops
helm upgrade --install --namespace ops prometheus-grafana prometheus-community/kube-prometheus-stack -f manifests/ops/grafana-custom.yml
helm upgrade --install --namespace ops loki grafana/loki-stack -f manifests/ops/loki-custom.yaml
helm upgrade --install --namespace ops promtail grafana/promtail -f manifests/ops/promtail-custom.yaml

#################### apps ####################
./k apply -f manifests/pechka
