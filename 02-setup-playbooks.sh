#!/bin/sh

source .env

ansible_hosts_yml=`cat playbooks/hosts_template.yml`

# raspi
host=$(ssh -o StrictHostKeyChecking=no nuage@pi-1.local -i .ssh/id_rsa "hostname -I" | awk '{print $1}')
ansible_hosts_yml=${ansible_hosts_yml//\[\[control-plane-1_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[control-plane-1_user\]\]/nuage}

host=$(ssh -o StrictHostKeyChecking=no nuage@pi-2.local -i .ssh/id_rsa "hostname -I" | awk '{print $1}')
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-2_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-2_user\]\]/nuage}

host=$(ssh -o StrictHostKeyChecking=no nuage@pi-3.local -i .ssh/id_rsa "hostname -I" | awk '{print $1}')
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-3_host\]\]/$host}
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-3_user\]\]/nuage}

# nuc
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-1_host\]\]/$NUC_HOST_IP}
ansible_hosts_yml=${ansible_hosts_yml//\[\[node-1_user\]\]/nuage}

# done
echo "$ansible_hosts_yml"
echo "$ansible_hosts_yml" > playbooks/hosts.yml
