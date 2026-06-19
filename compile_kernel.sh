#!/bin/bash
set -eo pipefail
KVER=$1
EL_VER=${KVER##*.}
. /etc/os-release
MY_MAJ_VER=${REDHAT_SUPPORT_PRODUCT_VERSION%%.*}
SPACE_NEEDED=15000

yum -y install 'dnf-command(config-manager)'
if [ $MY_MAJ_VER == 8 ] ; then
  yum config-manager --set-enabled powertools
else
  yum config-manager --set-enabled crb
fi

if [ $(df -BMiB --output=avail / | tail -n 1 | sed 's/MiB//') -gt $SPACE_NEEDED ] ; then
  yum -y install epel-release
  yum -y install rpm-build
  rpm -ivh "kernel-${KVER}.src.rpm"
  mkdir -p rpms/${KVER}
  cp "kernel-${KVER}.src.rpm" rpms/${KVER}
  # Install any extra dependencies
  for x in $(rpmbuild -bb --target=x86_64 --nobuild $HOME/rpmbuild/SPECS/kernel.spec 2>&1 | grep 'is needed' | cut -d ' ' -f 1) ; do yum -y install $x ; done
  for x in $(rpmbuild -bb --target=noarch --nobuild $HOME/rpmbuild/SPECS/kernel.spec 2>&1 | grep 'is needed' | cut -d ' ' -f 1) ; do yum -y install $x ; done

  export KVER
  rpmbuild -bb --clean --target=x86_64 --define="dist .$EL_VER" --without=cross_headers --without=selftests --without=kabichk --without=debuginfo --without=debug --without=realtime $HOME/rpmbuild/SPECS/kernel.spec
  mv ~/rpmbuild/RPMS/x86_64/* rpms/${KVER}/
  rpmbuild -bb --clean --target noarch --define="dist .$EL_VER" --with=abi_stablelists $HOME/rpmbuild/SPECS/kernel.spec
  mv $HOME/rpmbuild/RPMS/noarch/* rpms/${KVER}/
else
  echo "Not enough space to compile."
  exit 12
fi
