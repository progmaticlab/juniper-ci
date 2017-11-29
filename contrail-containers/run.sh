#!/bin/bash -ex

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ "$CLEAN_BEFORE" == 'true' || "$CLEAN_BEFORE" == 'clean_and_exit' ]] ; then
  $my_dir/${HOST}/cleanup.sh || /bin/true
  if [[ "$CLEAN_BEFORE" == 'clean_and_exit' ]] ; then
    exit
  fi
fi

rm -rf "$WORKSPACE/logs"
mkdir -p "$WORKSPACE/logs"

function save_logs() {
  source "$my_dir/${HOST}/ssh-defs"
  set +e
  # save common docker logs
  $SCP "$my_dir/__save-docker-logs.sh" $SSH_DEST:save-docker-logs.sh
  $SSH "./save-docker-logs.sh"

  # save env host specific logs
  # (should save into ~/logs folder on the SSH host)
  $my_dir/${HOST}/save-logs.sh

  # save to workspace
  if $SSH "sudo tar -cf logs.tar ./logs ; gzip logs.tar" ; then
    $SCP $SSH_DEST:logs.tar.gz "$WORKSPACE/logs/logs.tar.gz"
    pushd "$WORKSPACE/logs"
    tar -xf logs.tar.gz
    rm logs.tar.gz
    popd
  fi

  # save to workspace
  if $SSH_BUILD "sudo tar -cf logs.tar ./logs ; gzip logs.tar" ; then
    $SCP $SSH_DEST_BUILD:logs.tar.gz "$WORKSPACE/logs/build_logs.tar.gz"
    pushd "$WORKSPACE/logs"
    tar -xf build_logs.tar.gz
    rm build_logs.tar.gz
    popd
  fi
}

trap catch_errors ERR;
function catch_errors() {
  local exit_code=$?
  echo "Errors!" $exit_code $@

  save_logs
  if [[ "$CLEAN_ENV" == 'always' ]] ; then
    $my_dir/${HOST}/cleanup.sh
  fi

  exit $exit_code
}

$my_dir/${HOST}/create-vm.sh
source "$my_dir/${HOST}/ssh-defs"

for dest in ${SSH_DEST_WORKERS[@]} ; do
  # TODO: when repo be splitted to containers & build here will be containers repo only,
  # then build repo should be added to be copied below
  $SCP -r "$WORKSPACE/contrail-container-builder" ${dest}:./
done
$my_dir/${HOST}/setup-${WAY}-nodes.sh

$SCP "$my_dir/__containers-build.sh" $SSH_DEST_BUILD:containers-build.sh
$SCP -r "$WORKSPACE/contrail-build-poc" $SSH_DEST_BUILD:./

set -o pipefail
$SSH_BUILD "CONTRAIL_VERSION=$CONTRAIL_VERSION BUILD_PACKAGES=$BUILD_PACKAGES timeout -s 9 180m ./containers-build.sh" | tee $WORKSPACE/logs/build.log
set +o pipefail

# ceph.repo file is needed ONLY fow centos on aws.
$SCP "$my_dir/__ceph.repo" $SSH_DEST:ceph.repo
$SCP "$my_dir/__run-${WAY}-gate.sh" $SSH_DEST:run-${WAY}-gate.sh
timeout -s 9 60m $SSH "CONTRAIL_VERSION=$CONTRAIL_VERSION OPENSTACK_HELM_URL=$OPENSTACK_HELM_URL ./run-${WAY}-gate.sh $public_ip_build"

trap - ERR
save_logs
if [[ "$CLEAN_ENV" == 'always' || "$CLEAN_ENV" == 'on_success' ]] ; then
  $my_dir/${HOST}/cleanup.sh
fi
