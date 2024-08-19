#!/bin/sh

kubeadm reset --force
systemctl stop kubelet
rm -rf /etc/kubernetes/
rm -rf ~/.kube/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/cni/
rm -rf /etc/cni/
rm -rf /var/lib/etcd/
iptables -F && iptables -X
