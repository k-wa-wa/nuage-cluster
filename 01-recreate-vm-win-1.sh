#!/bin/sh

set -e

scp -F .ssh-host/config -r ./.ssh win-1:"C:\Users\nuage"
scp -F .ssh-host/config ./vm/win-1/Vagrantfile win-1:"C:\Users\nuage"

ssh -F .ssh-host/config win-1 'vagrant halt && vagrant destroy -f && vagrant up'
