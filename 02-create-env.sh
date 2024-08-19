#!/bin/sh
ansible_hosts_yml=`cat playbooks/hosts_template.yml`

# mac-1
vms=('node-1')
for vm in ${vms[@]}
do
  host=$(multipass info $vm | grep "192.168.xxx" | tr -d " " )
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_host\]\]/$host}
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_user\]\]/ubuntu}
done

# win-1
vms=('control-plane-2' 'node-2' 'control-plane-1')
for vm in ${vms[@]}
do
  host=$(ssh -F .ssh-host/config win-1 'vagrant ssh '${vm}' -c "hostname -I"' | sed 's/.*\(192\.168\.xxx\.[0-9]*\).*/\1/')
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_host\]\]/$host}
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_user\]\]/vagrant}
done

# intelmac-1
vms=('control-plane-3' 'node-3')
for vm in ${vms[@]}
do
  host=$(ssh -F .ssh-host/config intelmac-1 'export PATH=/usr/local/bin:$PATH; vagrant ssh '${vm}' -c "hostname -I"' | sed 's/.*\(192\.168\.xxx\.[0-9]*\).*/\1/')
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_host\]\]/$host}
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_user\]\]/vagrant}
done

# done
echo "$ansible_hosts_yml"
echo "$ansible_hosts_yml" > playbooks/hosts.yml
