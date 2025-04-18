#!/bin/bash

set -e
export KUBECONFIG=playbooks/k8s/admin.conf

#################### helm chat更新 ####################
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

#################### nodes ####################
./k apply -f manifests/node-labels.yaml

#################### postgres ####################
./k apply -f manifests/postgres/
./k wait --for=condition=Ready --timeout=300s pod/postgres-0
./k cp ./db/postgres/init.sh postgres-0:/tmp/init.sh
./k exec -it postgres-0 -- bash /tmp/init.sh

#################### 監視 ####################
./k get namespace ops 2>/dev/null || ./k create namespace ops
helm upgrade --install --namespace ops prometheus-grafana prometheus-community/kube-prometheus-stack \
  -f manifests/ops/prometheus-values.yaml
./k apply -f manifests/ops/grafana-custom.yaml
./k wait -n ops \
  --for=condition=Ready \
  --timeout=300s \
  -l "release=prometheus-grafana" \
  --all pod
helm upgrade --install --namespace ops loki grafana/loki-stack -f manifests/ops/loki-custom.yaml
helm upgrade --install --namespace ops promtail grafana/promtail -f manifests/ops/promtail-custom.yaml

#################### argo workflow ####################
./k get namespace argo 2>/dev/null || ./k create namespace argo
./k apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.2/quick-start-minimal.yaml
./k apply -n argo -f manifests/workflow

#################### apps ####################
./k apply -f manifests/nuage-dashboard.yaml
./k apply -f manifests/pechka/pv.yaml
./k apply -f manifests/pechka/file-server
./k scale deployment file-server-api-deployment --replicas=2
./k scale deployment file-server-ui-deployment --replicas=2
./k apply -n argo -f manifests/pechka/file-server-workflow
