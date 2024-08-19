#!/bin/sh

for i in {1..50}
do
    etcd=$(kubectl get pods -n kube-system | grep etcd || true)
    if [ "$etcd" == *Running* ]; then
        break
    fi
    sleep 10
done
