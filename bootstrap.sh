#!/bin/bash
KERNEL_VER=$1
EL_VER=$2
RPM_DIR=${3:-/rpms}
EL_MAJ_VER=${EL_VER%.*} ; EL_MIN_VER=${EL_VER#*.}
EL_UNDERVER=${EL_MAJ_VER}_${EL_MIN_VER}
KERNEL_MIN_VER=${KERNEL_VER%-*} ; KERNEL_MAJ_VER=${KERNEL_MIN_VER%.*}
KVER=${KERNEL_VER}.el${EL_UNDERVER}

yum -y install nano wget
mkdir $RPM_DIR
wget -N -O $RPM_DIR/kernel-$KVER.src.rpm https://dl.rockylinux.org/vault/rocky/${EL_VER}/BaseOS/source/tree/Packages/k/kernel-$KVER.src.rpm
