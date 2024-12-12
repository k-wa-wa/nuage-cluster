kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.0/install.yaml

kubectl create namespace argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml


# curl -X POST http://argo-server.argo.svc.cluster.local/example -d '{"message": "Hello, Argo!"}'
# curl -X POST http://localhost:2746/example -d '{"message": "Hello, Argo!"}'
