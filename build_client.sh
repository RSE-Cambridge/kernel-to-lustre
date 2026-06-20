#!/bin/bash
SCRIPT_DIR=$(dirname $(readlink -f $0))

EL_VER=9.7
KERNEL_VER=5.14.0-611.55.1
LUSTRE_VER=2.16.1
DOCA_VER=3.2.1
RPM_DIR=/src/rpms
WORK_DIR=/src/work
KVER=${KERNEL_VER}.el9_7

mkdir $WORK_DIR
mkdir $RPM_DIR

$SCRIPT_DIR/bootstrap.sh $KVER $RPM_DIR
$SCRIPT_DIR/compile_kernel.sh $KVER $RPM_DIR
$SCRIPT_DIR/compile_lustre_client.sh -w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -d $DOCA_VER -e $EL_VER
