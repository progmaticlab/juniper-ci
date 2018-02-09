#!/bin/bash -ex

# tune some host settings
sudo sysctl -w vm.max_map_count=1048575

registry_ip=${1:-localhost}
if [[ "$registry_ip" != 'localhost' ]] ; then
  sudo mkdir -p /etc/docker
  cat | sudo tee /etc/docker/daemon.json << EOF
{
    "insecure-registries": ["$registry_ip:5000"]
}
EOF
fi

if [[ -x $(command -v apt-get 2>/dev/null) ]]; then
  HOST_OS='ubuntu'
elif [[ -x $(command -v yum 2>/dev/null) ]]; then
  HOST_OS='centos'
else
  echo "ERROR: Unable to find apt-get or yum"
  exit 1
fi

echo "INFO: Preparing instances"
if [ "x$HOST_OS" == "xcentos" ]; then
  # ip is located in /usr/sbin that is not in path...
  export PATH=${PATH}:/usr/sbin
  sudo cp ./ceph.repo /etc/yum.repos.d/ceph.repo
fi

# TODO: switch to openstack's repo when work is done
git clone ${OPENSTACK_HELM_URL:-https://github.com/cloudscaling/openstack-helm}
cd openstack-helm

export OPENCONTRAIL_REGISTRY_URL="${registry_ip}:5000"
export INTEGRATION=aio
export INTEGRATION_TYPE=basic
export SDN_PLUGIN=opencontrail
#export GLANCE=pvc
#export PVC_BACKEND=ceph
err=0
./tools/gate/setup_gate.sh || err=$?

mv logs ../

exit $err
