#!/bin/sh

# Point at latest release
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
# Deploy the KubeVirt operator
./k apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
# Create the KubeVirt CR (instance deployment request) which triggers the actual installation
./k apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-cr.yaml
# wait until all KubeVirt components are up
./k -n kubevirt wait kv kubevirt --for condition=Available



export VERSION=$(basename $(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest))

./k apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/${VERSION}/cdi-operator.yaml
./k apply -f https://github.com/kubevirt/containerized-data-importer/releases/download/${VERSION}/cdi-cr.yaml
