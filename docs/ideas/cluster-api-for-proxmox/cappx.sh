# install k3s
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# install clusterctl
curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.10.3/clusterctl-linux-amd64 -o clusterctl
sudo install -o root -g root -m 0755 clusterctl /usr/local/bin/clusterctl

# install cluster-api components
export EXP_CLUSTER_RESOURCE_SET=true
clusterctl init --infrastructure=proxmox:v0.4.3 --config https://raw.githubusercontent.com/k8s-proxmox/cluster-api-provider-proxmox/main/clusterctl.yaml

# export env variables
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export CONTROLPLANE_HOST=192.168.5.210
export PROXMOX_URL=https://192.168.5.21:8006/api2/json
export PROXMOX_PASSWORD="xxx"
export PROXMOX_USER=xxx@pam

# generate manifests (available flags: --target-namespace, --kubernetes-version, --control-plane-machine-count, --worker-machine-count)
clusterctl generate cluster nuage-cluster \
    --control-plane-machine-count=3 \
    --worker-machine-count=3 \
    --infrastructure=proxmox:v0.4.3 \
    --config https://raw.githubusercontent.com/k8s-proxmox/cluster-api-provider-proxmox/main/clusterctl.yaml > nuage-cluster.yaml

# get workload cluster's kubeconfig
clusterctl get kubeconfig nuage-cluster > kubeconfig.yaml

# use weave-cni for this example
kubectl --kubeconfig=kubeconfig.yaml apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

# get node command for workload cluster
kubectl --kubeconfig=kubeconfig.yaml get node
