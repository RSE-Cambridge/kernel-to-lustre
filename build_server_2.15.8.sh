#!/bin/bash
SCRIPT_DIR=$(dirname $(readlink -f $0))

EL_VER=8.10
KERNEL_VER=4.18.0-553.82.1
LUSTRE_VER=2.17.0
DOCA_VER=3.2.1
RPM_DIR=/src/rpms
WORK_DIR=/work

mkdir $WORK_DIR
mkdir $RPM_DIR

$SCRIPT_DIR/bootstrap.sh $KERNEL_VER $EL_VER $RPM_DIR
$SCRIPT_DIR/compile_lustre_server.sh -w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -d $DOCA_VER -e $EL_VER
