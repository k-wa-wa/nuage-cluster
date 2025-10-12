#!/bin/bash

set -e

#################### ansible collection ####################
ansible-galaxy collection install prometheus.prometheus --force
ansible-galaxy collection install grafana.grafana --force

#################### helm chat更新 ####################
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
