
- [公式の手順](https://redis.io/docs/latest/operate/kubernetes/deployment/quick-start/)では、redislabs/operator がarmに対応しておらずうまくいかなかった

- 以下のredis operatorではうまくいった

```sh
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/

helm upgrade --install redis-operator ot-helm/redis-operator
helm upgrade --install redis-cluster ot-helm/redis-cluster \
  --set redisCluster.clusterSize=3
```
