#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/util.sh
. /etc/os-release
LOCAL_MAJ_VER=${VERSION_ID%.*}; LOCAL_MIN_VER=${VERSION_ID#*.}
echo_info "Executing on $LOCAL_MAJ_VER . $LOCAL_MIN_VER"

install_dependencies () {
local _EL_VER=$1 ; local _ARCH=$2
local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
echo_info "Installing dependencies ..."
if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
  echo_warn "OS major version mismatch: Installing dependencies for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
fi
yum -y install 'dnf-command(config-manager)'
if [ $LOCAL_MAJ_VER == 8 ] ; then
  yum config-manager --set-enabled powertools
else
  yum config-manager --set-enabled crb
fi
yum -y groupinstall "Development Tools"
yum clean packages
yum -y install sudo git wget createrepo rsync nano
yum clean packages
if [ $LOCAL_MAJ_VER -eq 8 ] ; then
  yum -y install nano #placeholder
else
  yum -y install perl-File-Copy perl-File-Compare perl-sigtrap kernel-srpm-macros
fi
yum clean packages
yum -y install libselinux-utils python3-libs python3-devel libtool kernel-devel kernel-headers pciutils kernel-rpm-macros gcc rpm-build make autoconf patch automake lsof ethtool
yum clean packages
yum -y install krb5-devel libmount libmount-devel libnl3-devel libyaml-devel
yum clean packages
yum -y install epel-release
yum clean packages
yum -y install dkms
yum clean packages
}

function clone_lustre_source() {
local _WORK_DIR=$1 ; local _LUSTRE_VER=$2
local _LUSTRE_REPO=${3:-git://git.whamcloud.com/fs/lustre-release.git}
echo_info "Cloning Lustre ..."
cd $_WORK_DIR
if [ ! -d lustre-release ] ; then
  git clone $_LUSTRE_REPO $_WORK_DIR/lustre-release/
  cd $_WORK_DIR/lustre-release/
  git checkout ${_LUSTRE_VER}
fi
cd $_WORK_DIR/lustre-release
git reset --hard
sh autogen.sh
export LUSTRE_SRC_DIR=$_WORK_DIR/lustre-release
echo_info "LUSTRE_SRC_DIR is $LUSTRE_SRC_DIR"
}

get_uri() {
  local _URI=$1
  local _DEST=$2
  echo_info "Wgetting $_URI to $_DEST ..."
  wget -r -N -np -nd -R "*.htm*,*.xml*,*.asc*,*.gz,*.bz2,*.txt" --directory-prefix=${_DEST} ${_URI}/
}

install_kernel() {
  local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _KERNEL_VER=$3 ; local _ARCH=$4
  local _RPM_DIR=${5:-/rpms}
  local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
  local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
  local _KERNEL_MIN_VER=${_KERNEL_VER%-*} ; local _KERNEL_MAJ_VER=${_KERNEL_MIN_VER%.*}
  local _KVER=${_KERNEL_VER}.el${_EL_UNDERVER}
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Building kernel for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi

  echo_info "Installing kernel ${_KVER} ..."
  cd $_RPM_DIR
  yum -y localinstall --skip-broken kernel*${ARCH}.rpm
}

install_doca() {
  local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _DOCA_VER=$3
  local _RPM_DIR=${4:-/rpms}
  local _DOCA_URI=${5:-https://linux.mellanox.com/public/repo/doca/}
  local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
  local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
  local _DOCA_DIR=${_WORK_DIR}/doca-${_DOCA_VER}
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Building kernel for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi

  echo_info "Installing doca ${_DOCA_VER} ..."
  cd $_WORK_DIR
  get_uri ${_DOCA_URI}/${_DOCA_VER}/rhel${_EL_MAJ_VER}/x86_64/ ${_DOCA_DIR}

  cat <<EOF | sudo tee /etc/yum.repos.d/doca.repo || true
[doca]
name=Remote DOCA
baseurl=${_DOCA_URI}/${_DOCA_VER}/rhel${_EL_MAJ_VER}/x86_64
enabled=1
gpgcheck=0
EOF

  yum -y install doca-ofed
  mv -v ${_DOCA_DIR}/*.rpm ${_RPM_DIR}
}

create_ofa_dkms() {
  local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _KERNEL_VER=$3 ; local _ARCH=$4
  local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
  local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
  local _KERNEL_MIN_VER=${_KERNEL_VER%-*} ; local _KERNEL_MAJ_VER=${_KERNEL_MIN_VER%.*}
  local _KVER=${_KERNEL_VER}.el${_EL_UNDERVER}
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Building kernel for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi

  echo_info "Doing DKMS build for ofa kernel ..."
  ofed_ver=$(dkms status -m mlnx-ofa_kernel | cut -d '/' -f 2 | cut -d ':' -f 1 | cut -d ',' -f 1)
  echo "dkms build -k $_KVER -m mlnx-ofa_kernel -v $ofed_ver --kernelsourcedir /lib/modules/${_KVER}.${_ARCH}/source/"
  dkms build -k $_KVER -m mlnx-ofa_kernel -v $ofed_ver --kernelsourcedir /lib/modules/${_KVER}.${_ARCH}/source/
}

compile_lustre() {
  local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _KERNEL_VER=$3 ; local _ARCH=$4
  local _RPM_DIR=${5:-/rpms}
  local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
  local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
  local _KERNEL_MIN_VER=${_KERNEL_VER%-*} ; local _KERNEL_MAJ_VER=${_KERNEL_MIN_VER%.*}
  local _KVER=${_KERNEL_VER}.el${_EL_UNDERVER}
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Building kernel for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi

  echo_info "Compiling lustre ..."
  cd ${WORK_DIR}/lustre-release
  sh autogen.sh
  ./configure --disable-server --enable-client --with-linux=/usr/src/kernels/${_KVER}.${_ARCH} --with-o2ib=/usr/src/ofa_kernel/default
  make rpms dkms-rpms
  cp -rv *.rpm ${_RPM_DIR}
}

function usage () {
echo "Usage: $0 -r <RPM_output_dir> -w <working_dir>"
echo "          -l <lustre_version> -d <doca_version>"
echo "          -k <kernel_version>"
echo "          -e <EL_version>"
exit 255
}

#main
WORK_DIR=/dev/shm
RPM_DIR=/rpms
_ARCH=x86_64
DOCA_URL="https://linux.mellanox.com/public/repo/doca/"
LUSTRE_URL="git://git.whamcloud.com/fs/lustre-release.git"
while getopts ":r:w:l:d:k:e:E:a:K:L:D:" opt; do
    case "${opt}" in
        r)
            RPM_DIR=${OPTARG}
            ;;
        w)
            WORK_DIR=${OPTARG}
            ;;
        l)
            LUSTRE_VER=${OPTARG}
            ;;
        d)
            DOCA_VER=${OPTARG}
            ;;
        k)
            KERNEL_VER=${OPTARG}
            ;;
        e)
            EL_VER=${OPTARG}
            ;;
        a)
            if [ -n "${OPTARG}" ] ; then
              _ARCH=${OPTARG}
            fi
            ;;
        L)
            if [ -n "${OPTARG}" ] ; then
              LUSTRE_URL=${OPTARG}
            fi
            ;;
        K)
            if [ -n "${OPTARG}" ] ; then
              KERNEL_URL=${OPTARG}
            fi
            ;;
        D)
            if [ -n "${OPTARG}" ] ; then
              DOCA_URL=${OPTARG}
            fi
            ;;
        *)
            usage
            ;;
    esac
done

echo "-w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -d $DOCA_VER -e $EL_VER -a $_ARCH"

if [ -z "$WORK_DIR" ] || [ -z "$RPM_DIR" ] || [ -z "$LUSTRE_VER" ] || [ -z "$KERNEL_VER" ] || \
   [ -z "$DOCA_VER" ] || [ -z "$EL_VER" ] || [ -z "$_ARCH" ] ; then
  usage
  exit 255
fi

mkdir -p $RPM_DIR

install_dependencies $EL_VER $_ARCH
install_kernel $WORK_DIR $EL_VER $KERNEL_VER $_ARCH $RPM_DIR
install_doca $WORK_DIR $EL_VER $DOCA_VER $RPM_DIR $DOCA_URL
create_ofa_dkms $WORK_DIR $EL_VER $KERNEL_VER $_ARCH
clone_lustre_source $WORK_DIR $LUSTRE_VER $LUSTRE_URL
compile_lustre $WORK_DIR $EL_VER $KERNEL_VER $_ARCH $RPM_DIR
