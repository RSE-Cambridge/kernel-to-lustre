#!/bin/bash
SCRIPT_DIR=$(dirname $(readlink -f $0))

EL_VER=9.6
KERNEL_VER=5.14.0-570.129.1
LUSTRE_VER=2.17.0
DOCA_VER=3.4.0
RPM_DIR=/src/rpms/IB/5.14.0-570.129.1.el9_6/
WORK_DIR=/work

mkdir $WORK_DIR
mkdir -p $RPM_DIR

$SCRIPT_DIR/bootstrap.sh $KERNEL_VER $EL_VER $RPM_DIR
$SCRIPT_DIR/compile_kernel.sh $KERNEL_VER $EL_VER $RPM_DIR
$SCRIPT_DIR/compile_lustre_client.sh -w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -d $DOCA_VER -e $EL_VER
