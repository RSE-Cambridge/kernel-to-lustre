#!/bin/bash
SCRIPT_DIR=$(dirname $(readlink -f $0))
SCRIPT_NAME=$(basename $(readlink -f $0))

TOKEN_FILE=/root/.rhel_api_token
WORK_DIR=/work
EL_VER=9.6
LUSTRE_VER=2.17.0
DOCA_VER=3.4.0
EL_MAJ_VER=${EL_VER%.*} ; EL_MIN_VER=${EL_VER#*.}
EL_UNDERVER=${EL_MAJ_VER}_${EL_MIN_VER}

if [ -z $container ] ; then
  echo "Running this script inside a container ..."
  docker run --env-file="$TOKEN_FILE" -v "$SCRIPT_DIR:/src:rw" -it "rockylinux:$EL_VER" "/src/$SCRIPT_NAME"
else
  echo "Running in container type: $container"
  yum -y install python3-requests

  mkdir -p $WORK_DIR
  cd $WORK_DIR
  KVER=$($SCRIPT_DIR/get_errata.py $EL_MAJ_VER -m $EL_MIN_VER)
  KERNEL_VER=${KVER%.*}

  RPM_DIR=/src/rpms/IB/$KVER/
  if ! [ -e $RPM_DIR ] ; then
    mkdir -p $RPM_DIR
    mv kernel-$KVER.src.rpm $RPM_DIR
    echo $SCRIPT_DIR/compile_kernel.sh $KERNEL_VER $EL_VER $RPM_DIR
    $SCRIPT_DIR/compile_kernel.sh $KERNEL_VER $EL_VER $RPM_DIR
    echo $SCRIPT_DIR/compile_lustre_client.sh -w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -d $DOCA_VER -e $EL_VER
    $SCRIPT_DIR/compile_lustre_client.sh -w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -d $DOCA_VER -e $EL_VER
  fi
fi
