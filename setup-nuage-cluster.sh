#!/bin/sh

set -e

bash ./01-recreate-vm-m1mac-1.sh
bash ./01-recreate-vm-win-1.sh
bash ./01-recreate-vm-intelmac-1.sh
wait

bash ./02-create-env.sh

bash ./03-setup-cluster.sh
