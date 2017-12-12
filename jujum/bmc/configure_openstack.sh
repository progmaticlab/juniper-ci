#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/functions"
source "$my_dir/../common/functions"

export WORKSPACE="${WORKSPACE:-$HOME}"
# prepare environment for common openstack functions
OPENSTACK_VERSION="$VERSION"
SSH_CMD="juju-ssh"
export PASSWORD=password

cd $WORKSPACE
create_stackrc
source $WORKSPACE/stackrc

virtualenv .venv
source .venv/bin/activate
pip install python-openstackclient

openstack catalog list

openstack project create demo
openstack role add --project demo --user admin Member

openstack network create --share --external --provider-network-type flat --provider-physical-network external public
openstack subnet create --network public --subnet-range $public_network_addr.0/24 --no-dhcp --gateway $public_network_addr.1 public

openstack flavor create --ram 256 --vcpus 1 --public small

rm cirros-0.3.5-x86_64-disk.img
wget -nv http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
openstack image create --public --file cirros-0.3.5-x86_64-disk.img cirros

export OS_PROJECT_NAME=demo

openstack network create private1
openstack subnet create --network private1 --subnet-range 192.168.1.0/24 --gateway 192.168.1.1 private1

openstack network create private2
openstack subnet create --network private2 --subnet-range 192.168.2.0/24 --gateway 192.168.2.1 private2

openstack router create rt
openstack router set --external-gateway public rt
openstack router add subnet rt private1
openstack router add subnet rt private2

openstack server create --image cirros --flavor small --network private1 --min 2 --max 2 ttt
sleep 10
openstack server create --image cirros --flavor small --network private2 --min 2 --max 2 rrr
sleep 10
openstack server list
