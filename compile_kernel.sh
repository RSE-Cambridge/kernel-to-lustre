#!/bin/bash
set -eo pipefail
KERNEL_VER=$1
EL_VER=$2

EL_MAJ_VER=${EL_VER%.*} ; EL_MIN_VER=${EL_VER#*.}
EL_UNDERVER=${EL_MAJ_VER}_${EL_MIN_VER}
KVER=${KERNEL_VER}.el${EL_UNDERVER}

RPM_DIR=${3:-/rpms}
. /etc/os-release
MY_MAJ_VER=${REDHAT_SUPPORT_PRODUCT_VERSION%%.*}
SPACE_NEEDED=15000

yum -y install 'dnf-command(config-manager)'
if [ $MY_MAJ_VER == 8 ] ; then
  yum config-manager --set-enabled powertools
else
  yum config-manager --set-enabled crb
fi

if [ $(df -BMiB --output=avail $HOME | tail -n 1 | sed 's/MiB//') -gt $SPACE_NEEDED ] ; then
  yum -y install epel-release
  yum -y install rpm-build
  rpm -ivh "$RPM_DIR/kernel-${KVER}.src.rpm"
  # Install any extra dependencies
  for x in $(rpmbuild -bb --target=x86_64 --nobuild $HOME/rpmbuild/SPECS/kernel.spec 2>&1 | grep 'is needed' | cut -d ' ' -f 1) ; do yum -y install $x ; done
  for x in $(rpmbuild -bb --target=noarch --nobuild $HOME/rpmbuild/SPECS/kernel.spec 2>&1 | grep 'is needed' | cut -d ' ' -f 1) ; do yum -y install $x ; done

  export KVER
  rpmbuild -bb --clean --target=x86_64 --define="dist .el$EL_UNDERVER" --without=cross_headers --without=selftests --without=kabichk --without=debuginfo --without=debug --without=realtime $HOME/rpmbuild/SPECS/kernel.spec
  mv $HOME/rpmbuild/RPMS/x86_64/* $RPM_DIR/
  rpmbuild -bb --clean --target noarch --define="dist .el$EL_UNDERVER" --with=abi_stablelists $HOME/rpmbuild/SPECS/kernel.spec
  mv $HOME/rpmbuild/RPMS/noarch/* $RPM_DIR/
else
  echo "Not enough space to compile."
  exit 12
fi
