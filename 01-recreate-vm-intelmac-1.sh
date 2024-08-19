#!/bin/sh

set -e

scp -F .ssh-host/config -r ./.ssh intelmac-1:"~/"
scp -F .ssh-host/config ./vm/intelmac-1/Vagrantfile intelmac-1:"~/"

ssh -F .ssh-host/config intelmac-1 'export PATH=/usr/local/bin:$PATH; vagrant halt && vagrant destroy -f && vagrant up'
