#!/bin/bash
KVER=$1
RPM_DIR=${2:-/rpms}
yum -y install nano wget
mkdir $RPM_DIR
wget -N -np -nd -O $RPM_DIR/kernel-$KVER.src.rpm https://dl.rockylinux.org/vault/rocky/9.7/BaseOS/source/tree/Packages/k/kernel-$KVER.src.rpm
