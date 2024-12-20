#!/bin/sh

set -e

kubectl get namespace argocd || kubectl create namespace argocd

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

for i in {1.30}
do
  password=$(kubectl -n argocd get secret/argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo || "")
  if [ $password != '' ];then
    echo $password
    break
  fi

  sleep 3
done
