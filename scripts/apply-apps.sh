#!/bin/sh

set -e
export KUBECONFIG=playbooks/k8s/admin.conf

#################### helm chat更新 ####################
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

#################### postgres operator ####################
./k get namespace postgres 2>/dev/null || ./k create namespace postgres
helm upgrade --install -n postgres postgres-operator postgres-operator-charts/postgres-operator
helm upgrade --install -n postgres postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui
helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.5.151 \
    --set nfs.path=/srv/nfs/pv
./k patch storageclass nfs-client -p '{"metadata": {"annotations": {"storageclass.beta.kubernetes.io/is-default-class": "true"}}}'
./k apply -n postgres -f manifests/postgres.yaml

# dbの初期化、secretを他namespaceにコピー
./k wait -n postgres \
  --for=condition=Ready \
  --timeout=300s \
  pod/nuage-postgres-0
./k cp ./db/postgres/init.sh nuage-postgres-0:/tmp/init.sh -n postgres
./k exec -it nuage-postgres-0 -n postgres -- bash /tmp/init.sh
./k delete secret postgres.nuage-postgres.credentials.postgresql.acid.zalan.do --ignore-not-found
./k get secret postgres.nuage-postgres.credentials.postgresql.acid.zalan.do -n postgres -o yaml \
  | sed "s/namespace: postgres/namespace: default/g" | ./k apply -f -

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
./k apply -f manifests/pechka/file-server
./k apply -n argo -f manifests/pechka/file-server-workflow
