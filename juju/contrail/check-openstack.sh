#!/bin/bash -e

my_file="${BASH_SOURCE[0]}"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/functions"
source "$my_dir/../common/functions-openstack"

# for simple setup you can setup MASQUERADING on compute hosts?
#juju-ssh $m2 "sudo iptables -t nat -A POSTROUTING -o vhost0 -j MASQUERADE"
#juju-ssh $m3 "sudo iptables -t nat -A POSTROUTING -o vhost0 -j MASQUERADE"

if [ -z "$WORKSPACE" ] ; then
  export WORKSPACE="$HOME"
fi

cd $WORKSPACE
create_stackrc
source $WORKSPACE/stackrc
create_virtualenv

run_os_checks
