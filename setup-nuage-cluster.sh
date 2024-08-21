#!/bin/sh

set -e

bash ./01-recreate-vm-intelmac-1.sh

bash ./02-create-env.sh

bash ./03-setup-cluster.sh
