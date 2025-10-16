#!/bin/bash

set -e
export KUBECONFIG=playbooks/admin.conf

#################### nodes ####################
./k apply -f manifests/node-labels.yaml
./k apply -f manifests/namespaces.yaml

#################### istio ####################
if ! ./k get ns istio-system &> /dev/null; then
  ./istio-1.26.2/bin/istioctl install -y -f istio-1.26.2/istio-custom.yaml
fi
./k apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.0/cert-manager.yaml
./k apply -f istio-1.26.2/samples/addons

#################### argocd ####################
helm upgrade --install -n argocd argocd argo/argo-cd -f manifests/argocd/argocd-values.yaml
./k apply -f manifests/argocd/apps/

./k apply -k manifests/secrets

#################### postgres ####################
./k apply -f manifests/postgres/
./k wait --for=condition=Ready --timeout=300s pod/postgres-0
./k cp ./db/postgres/init.sh postgres-0:/tmp/init.sh
./k exec -it postgres-0 -- bash /tmp/init.sh

#################### apps: dashboard ####################
./k apply -f manifests/dashboard-v2

#################### apps: pechka ####################
# argo workflow
curl -L https://github.com/argoproj/argo-workflows/releases/download/v3.6.2/quick-start-minimal.yaml \
  | sed 's/namespace: argo/namespace: pechka/g' \
  | ./k apply -n pechka -f -

# apps
./k apply -n pechka -f manifests/pechka
./k apply -f manifests/pechka/file-server-workflow

# ./k scale -n pechka deployment file-server-api --replicas=2
# ./k scale -n pechka deployment file-server-ui --replicas=2
