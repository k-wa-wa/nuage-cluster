#!/bin/bash

set -e

#################### helm chat更新 ####################
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

#################### proxmox ve ####################
(
    cd terraform/environments/prerequire \
    && tofu apply --auto-approve
)
