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

#TODO: move NUM (option server HOST) to job params
$my_dir/${HOST}/create-vm.sh
source "$my_dir/${HOST}/ssh-defs"

$SCP "$my_dir/__containers-build.sh" $SSH_DEST_BUILD:containers-build.sh
if [[ "$WAY" == 'helm' ]] ; then
  # helm's gating is not very fast. it takes more than 25 minutes. we can build containers in background.
  echo "INFO: ($(date)) run build in background then wait some time and run helm gating"
  $SSH_BUILD "CONTRAIL_VERSION=$CONTRAIL_VERSION DOCKER_CONTRAIL_URL=$DOCKER_CONTRAIL_URL timeout -s 9 60m ./containers-build.sh" &>$WORKSPACE/logs/build.log &
  # wait some time while it prepares vrouter.ko on www that is needed for gate in the beginning
  timeout -s 9 300 tail -f $WORKSPACE/logs/build.log || /bin/true
  echo "INFO: ($(date)) continuing with helm deployment"
else
  $SSH_BUILD "CONTRAIL_VERSION=$CONTRAIL_VERSION DOCKER_CONTRAIL_URL=$DOCKER_CONTRAIL_URL timeout -s 9 60m ./containers-build.sh"
fi

# ceph.repo file is needed ONLY fow centos on aws.
$SCP "$my_dir/__ceph.repo" $SSH_DEST:ceph.repo
$SCP "$my_dir/__run-${WAY}-gate.sh" $SSH_DEST:run-${WAY}-gate.sh
timeout -s 9 60m $SSH "CONTRAIL_VERSION=$CONTRAIL_VERSION CHANGE_REF=$CHANGE_REF OPENSTACK_HELM_URL=$OPENSTACK_HELM_URL ./run-${WAY}-gate.sh $public_ip_build"

trap - ERR
save_logs
if [[ "$CLEAN_ENV" == 'always' || "$CLEAN_ENV" == 'on_success' ]] ; then
  $my_dir/${HOST}/cleanup.sh
fi
