# kube-vip

```sh
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml

export VIP=192.168.xxx.xxx
export KVVERSION=v0.8.2

alias kube-vip="ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"

kube-vip manifest daemonset \
    --address $VIP \
    --inCluster \
    --taint \
    --controlplane \
    --services \
    --arp \
    --leaderElection >> kube-vip.yaml
kubectl apply -f kube-vip.yaml
```

`--interface $INTERFACE`を指定しないことで、各ノードでインターフェース名が異なっていても自動で選択させる
