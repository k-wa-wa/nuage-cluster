#!/bin/sh

set -e

bash ./01-setup-nodes.sh

bash ./02-create-env.sh

bash ./03-setup-cluster.sh

baseh ./04-apply-apps.sh
