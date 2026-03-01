#!/bin/sh
set -e

# install ROCm
sudo apt update
sudo apt -y install "linux-headers-$(uname -r)" "linux-modules-extra-$(uname -r)"
sudo apt -y install python3-setuptools python3-wheel
sudo usermod -a -G render,video $LOGNAME
wget https://repo.radeon.com/amdgpu-install/6.3.3/ubuntu/noble/amdgpu-install_6.3.60303-1_all.deb
sudo apt -y install ./amdgpu-install_6.3.60303-1_all.deb
sudo apt update
sudo apt -y install amdgpu-dkms rocm

# install ollama
curl -fsSL https://ollama.com/install.sh | sh
