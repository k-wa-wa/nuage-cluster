#!/bin/bash
set -eu

(
    cd terraform/environments/cluster \
    && tofu destroy --auto-approve
)
