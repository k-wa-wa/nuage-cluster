#!/bin/sh
set -e

# delete VMs
for vm in 'control-plane-1' 'node-1'
do
  multipass stop $vm || true # `|| true` でエラーを無視
  multipass delete $vm || true # `|| true` でエラーを無視
done
multipass purge

# create VMs
# multipass launch focal --cpus 2 --disk 10G --memory 4G --name control-plane-1 --bridged --cloud-init - <<EOF
# ssh_authorized_keys:
#   - $(cat ./.ssh/id_rsa.pub)
# EOF

multipass launch focal --cpus 2 --disk 40G --memory 4G --name node-1 --bridged --cloud-init - <<EOF
ssh_authorized_keys:
  - $(cat ./.ssh/id_rsa.pub)
EOF
