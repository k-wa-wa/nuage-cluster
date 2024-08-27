#!/bin/sh

set -e

minikube start
minikube addons enable ingress

kubectl apply -f manifests/pechka

kubectl apply -f manifests/ingress.yaml
minikube tunnel # -> http://localhost

# minikube delete
