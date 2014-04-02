# Package build instructions

## clone source
    git clone https://bitbucket.org/vnaum/libvirt-1.2.1.git -b master /mnt/src/libvirt
    git clone https://bitbucket.org/vnaum/nova.git -b xmas-demo /mnt/src/nova
    git clone https://bitbucket.org/vnaum/sns-neutron.git -b sns-agent1 /mnt/src/sns-neutron
    git clone https://github.com/vnaum/qemu.git -b vhost-user-v8 /mnt/src/qemu
    git clone https://github.com/SnabbCo/snabbswitch.git -b master /mnt/src/snabbswitch

## prepare build dependencies
    apt-get build-dep libvirt qemu neutron nova

## build
    cd /mnt/src/qemu && debuild binary
    cd /mnt/src/nova && debuild binary
    cd /mnt/src/sns-neutron && debuild binary
    cd /mnt/src/libvirt && debuild binary
    cd /mnt/src/snabbswitch && debuild binary
