#!/bin/sh

set -e

kubectl apply -f https://kube-vip.io/manifests/rbac.yaml

export VIP=192.168.5.50
export KVVERSION=v0.8.2

ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest daemonset \
    --address $VIP \
    --inCluster \
    --taint \
    --controlplane \
    --services \
    --arp \
    --leaderElection > kube-vip.yaml
kubectl apply -f kube-vip.yaml

kubectl wait -n kube-system \
  --for=condition=Ready \
  --timeout=300s \
  -l app.kubernetes.io/name=kube-vip-ds \
  --all pod
