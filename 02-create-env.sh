#!/bin/sh
ansible_hosts_yml=`cat playbooks/hosts_template.yml`

# raspi
host=$(ssh -o StrictHostKeyChecking=no nuage@pi-1.local -i .ssh/id_rsa "hostname -I")
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-1_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-1_user\]\]/nuage}

host=$(ssh -o StrictHostKeyChecking=no nuage@pi-2.local -i .ssh/id_rsa "hostname -I")
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-2_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-2_user\]\]/nuage}

host=$(ssh -o StrictHostKeyChecking=no nuage@pi-3.local -i .ssh/id_rsa "hostname -I")
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-3_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-3_user\]\]/nuage}

# intelmac-1
vms=('node-4')
for vm in ${vms[@]}
do
  host=$(ssh -F .ssh-host/config intelmac-1 'export PATH=/usr/local/bin:$PATH; vagrant ssh '${vm}' -c "hostname -I"' | sed 's/.*\(192\.168\.xxx\.[0-9]*\).*/\1/')
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_host\]\]/$host}
  ansible_hosts_yml=${ansible_hosts_yml//\[\["$vm"_user\]\]/vagrant}
done

host=192.168.xxx.xxx
ansible_hosts_yml=${ansible_hosts_yml//\[\[control-plane-1_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[control-plane-1_user\]\]/nuage}

# done
echo "$ansible_hosts_yml"
echo "$ansible_hosts_yml" > playbooks/hosts.yml
