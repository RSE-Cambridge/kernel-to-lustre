#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/util.sh
. /etc/os-release
LOCAL_MAJ_VER=${VERSION_ID%.*}; LOCAL_MIN_VER=${VERSION_ID#*.}
echo_info "Executing on $LOCAL_MAJ_VER . $LOCAL_MIN_VER"

function install_dependencies () {
local _EL_VER=$1 ; local _ARCH=$2 ; local _E2FS_VER=${3:-latest} ; local _RPM_DIR=${4:-/rpms}
local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
local _E2FS_DASHVER=${_E2FS_VER%.*}-${_E2FS_VER##*.}
  echo_info "Installing dependencies ..."
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Installing dependencies for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi
  yum -y update --exclude 'kernel*'
  yum -y install 'dnf-command(config-manager)'
  if [ $LOCAL_MAJ_VER -eq 8 ] ; then
    yum config-manager --set-enabled powertools
  else
    yum config-manager --set-enabled crb
  fi
  yum -y groupinstall "Development Tools"
  yum -y install epel-release
  yum clean packages
  yum -y install gcc autoconf libtool which wget make patch diffutils file binutils-devel python3-devel elfutils-devel libselinux-devel libaio-devel dnf-plugins-core bc bison flex git nano screen libyaml-devel libnl3-devel libmount-devel json-c-devel
  if [ $LOCAL_MAJ_VER -eq 8 ] ; then
    yum -y install python38 redhat-lsb python2 kernel-abi-whitelists
  else
    yum -y install python3 WALinuxAgent-cvm dracut centos-sb-certs gcc-plugin-devel glibc-static hmaccalc lvm2 system-sb-certs systemd-boot-unsigned tpm2-tools keyutils-libs-devel kernel-abi-stablelists systemd-ukify
  fi
  yum clean packages
  yum -y install libssh-devel libattr-devel libtirpc-devel libblkid-devel openssl-devel libuuid-devel texinfo texinfo-tex audit-libs-devel binutils-devel elfutils-devel kabi-dw ncurses-devel newt-devel numactl-devel openssl-devel pciutils-devel perl
  yum clean packages
  yum -y install  perl-devel python3-docutils xmlto xz-devel elfutils-libelf-devel libcap-devel libcap-ng-devel llvm-toolset libyaml libyaml-devel kernel-rpm-macros bpftool dwarves java-devel libbabeltrace-devel libbpf-devel
  yum clean packages
  yum -y install libmnl-devel net-tools rsync ccache linux-firmware createrepo pciutils ethtool gcc-gfortran tk libtraceevent-devel openmpi-devel lsof findutils sudo pinentry gnupg2
  yum clean packages
  E2FSPROGS_PATH="https://downloads.whamcloud.com/public/e2fsprogs/${_E2FS_VER}"
  E2FS_PATHS=''
  get_uri ${E2FSPROGS_PATH}/el${_EL_MAJ_VER}/RPMS/${_ARCH}/ ${_RPM_DIR}
  for package in e2fsprogs e2fsprogs-libs libcom_err libss libcom_err-devel e2fsprogs-devel ; do
    E2FS_PATHS="${_RPM_DIR}/${package}-[0-9]*.rpm $E2FS_PATHS"
  done
  yum -y localinstall ${E2FS_PATHS}
  yum clean packages
}

get_uri() {
  local _URI=$1
  local _DEST=$2
  echo_info "Wgetting $_URI to $_DEST ..."
  wget -r -N -np -nd -R "*.htm*,*.xml*,*.asc*,*.gz,*.bz2,*.txt,*.pub,sha256sum" --directory-prefix=${_DEST} ${_URI}/
}

function clone_lustre_source() {
local _WORK_DIR=$1 ; local _LUSTRE_VER=$2
local _LUSTRE_REPO=${3:-git://git.whamcloud.com/fs/lustre-release.git}
  echo_info "Cloning Lustre ..."
  cd $_WORK_DIR
  if [ ! -d lustre-release ] ; then
    git clone $_LUSTRE_REPO $_WORK_DIR/lustre-release/
  fi
  cd $_WORK_DIR/lustre-release
  git checkout ${_LUSTRE_VER}
  git reset --hard
  sh autogen.sh
  export LUSTRE_SRC_DIR=$_WORK_DIR/lustre-release
  echo_info "LUSTRE_SRC_DIR is $LUSTRE_SRC_DIR"
}

install_doca() {
  local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _DOCA_VER=$3
  local _RPM_DIR=${4:-/rpms}
  local _DOCA_URI=${5:-https://linux.mellanox.com/public/repo/doca/}
  local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
  local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Building kernel for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi

  echo_info "Installing doca ${_DOCA_VER} ..."
  cd $_WORK_DIR
  get_uri ${_DOCA_URI}/${_DOCA_VER}/rhel${_EL_MAJ_VER}/x86_64/ ${_RPM_DIR}

  cat <<EOF | sudo tee /etc/yum.repos.d/doca.repo || true
[doca]
name=Remote DOCA
baseurl=${_DOCA_URI}/${_DOCA_VER}/rhel${_EL_MAJ_VER}/x86_64
enabled=1
gpgcheck=0
EOF

  yum -y install mlnx-ofa_kernel-source mlnx-ofa_kernel-devel
}

function compile_kernel() {
local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _KERNEL_VER=$3 ; local _ARCH=$4
local _RPM_DIR=${5:-/rpms}
local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
local _KERNEL_MIN_VER=${_KERNEL_VER%-*} ; local _KERNEL_MAJ_VER=${_KERNEL_MIN_VER%.*}
local _KVER=${_KERNEL_VER}.el${_EL_UNDERVER}
  if [ $_EL_MAJ_VER != $LOCAL_MAJ_VER ] ; then
    echo_warn "OS major version mismatch: Building kernel for $_EL_MAJ_VER on $LOCAL_MAJ_VER"
  fi
  if [ $LOCAL_MAJ_VER -eq 8 ] ; then
    KERNEL_NAME=${_KVER}/linux-${_KERNEL_VER}.el${_EL_MAJ_VER}_lustre.${_ARCH}
  else
    KERNEL_NAME=${_KVER}/linux-${_KERNEL_VER}_lustre.el${_EL_MAJ_VER}.${_ARCH}
  fi
  cd $_WORK_DIR
  if [ -d kernel ] ; then mv kernel kernel-$(date +%s) ; fi
  mkdir -p $_WORK_DIR/kernel/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
  echo "%_topdir $WORK_DIR/kernel/rpmbuild" > ~/.rpmmacros
  rm -fv /var/tmp/rpm-tmp.*
  rpm -ivh "$_RPM_DIR/kernel-${_KVER}.src.rpm"
  cd $_WORK_DIR/kernel/rpmbuild/
  echo_info 'Prepping ...'
  rpmbuild -bp --target=${_ARCH} ./SPECS/kernel.spec
    cp $_WORK_DIR/kernel/rpmbuild/BUILD/kernel-${KERNEL_NAME}/configs/kernel-${_KERNEL_MIN_VER}-${_ARCH}.config $_WORK_DIR/lustre-release/lustre/kernel_patches/kernel_configs/kernel-${_KERNEL_MIN_VER}-${_KERNEL_MAJ_VER}-rhel${_EL_VER}-${_ARCH}.config
  echo_info 'Prepping done'
  sed -i '/# IO Schedulers/a CONFIG_IOSCHED_DEADLINE=y\nCONFIG_DEFAULT_IOSCHED="deadline"' $_WORK_DIR/lustre-release/lustre/kernel_patches/kernel_configs/kernel-${_KERNEL_MIN_VER}-${_KERNEL_MAJ_VER}-rhel${_EL_VER}-${_ARCH}.config
  echo '' > $_WORK_DIR/kernel/rpmbuild/SOURCES/patch-${_KERNEL_MIN_VER}-lustre.patch
  for patch in $(<"$_WORK_DIR/lustre-release/lustre/kernel_patches/series/${_KERNEL_MAJ_VER}-rhel${_EL_VER}.series"); do
    patch_file="$_WORK_DIR/lustre-release/lustre/kernel_patches/patches/${patch}"
    cat "${patch_file}" >> "$_WORK_DIR/kernel/rpmbuild/SOURCES/patch-${_KERNEL_MIN_VER}-lustre.patch"
  done

  sed -i.inst -e '/^    find $RPM_BUILD_ROOT\/lib\/modules\/$KernelVer/a\
  cp -a fs/ext4/* $RPM_BUILD_ROOT/lib/modules/$KernelVer/build/fs/ext4\
  rm -f $RPM_BUILD_ROOT/lib/modules/$KernelVer/build/fs/ext4/ext4-inode-test*' -e '/^# empty final patch to facilitate testing of kernel patches/i\
Patch99995: patch-%{version}-lustre.patch' -e '/^ApplyOptionalPatch linux-kernel-test.patch/i\
ApplyOptionalPatch patch-%{version}-lustre.patch' $_WORK_DIR/kernel/rpmbuild/SPECS/kernel.spec

echo "# ${_ARCH}" > $_WORK_DIR/kernel/rpmbuild/SOURCES/kernel-${_KERNEL_MIN_VER}-${_ARCH}.config
  cat $_WORK_DIR/lustre-release/lustre/kernel_patches/kernel_configs/kernel-${_KERNEL_MIN_VER}-${_KERNEL_MAJ_VER}-rhel${_EL_VER}-${_ARCH}.config >> $_WORK_DIR/kernel/rpmbuild/SOURCES/kernel-${_KERNEL_MIN_VER}-${_ARCH}.config
  cd $_WORK_DIR/kernel/rpmbuild

  echo_info 'Building ...'
  rpmbuild -ba --with firmware --target ${_ARCH} --with baseonly --without kabichk --define "buildid _lustre" $_WORK_DIR/kernel/rpmbuild/SPECS/kernel.spec
  mv -v $_WORK_DIR/kernel/rpmbuild/RPMS/${_ARCH}/*.rpm $_RPM_DIR
  mv -v $_WORK_DIR/kernel/rpmbuild/SRPMS/*.rpm $_RPM_DIR

  echo_info 'Installing kernel for Lustre build ...'
  KPATHS=''
  export KERNEL_SRC_DIR=$_WORK_DIR/kernel/rpmbuild/BUILD/kernel-${KERNEL_NAME}
  echo_info "KERNEL_SRC_DIR is $KERNEL_SRC_DIR"
  if [ $LOCAL_MAJ_VER -eq 8 ] ; then
    for package in kernel kernel-core kernel-devel kernel-modules ; do
      KPATHS="$_RPM_DIR/$package-${_KERNEL_VER}.el${_EL_MAJ_VER}_lustre.${_ARCH}.rpm $KPATHS"
    done
    yum -y localinstall $KPATHS
  else
    for package in kernel kernel-core kernel-devel kernel-modules kernel-modules-core ; do
      KPATHS="$_RPM_DIR/$package-${_KERNEL_VER}_lustre.el${_EL_MAJ_VER}.${_ARCH}.rpm $KPATHS"
    done
    yum -y localinstall $KPATHS
  fi
}

function compile_lustre (){
local _WORK_DIR=$1 ; local _EL_VER=$2 ; local _KERNEL_VER=$3 ; local _ARCH=$4
local _RPM_DIR=${5:-/rpms}
local _EL_MAJ_VER=${_EL_VER%.*} ; local _EL_MIN_VER=${_EL_VER#*.}
local _EL_UNDERVER=${_EL_MAJ_VER}_${_EL_MIN_VER}
local _KERNEL_MIN_VER=${_KERNEL_VER%-*} ; local _KERNEL_MAJ_VER=${_KERNEL_MIN_VER%.*}
local _KVER=${_KERNEL_VER}.el${_EL_UNDERVER}

  if [ $LOCAL_MAJ_VER -eq 8 ] ; then
    KERNEL_NAME=${_KVER}/linux-${_KERNEL_VER}.el${_EL_MAJ_VER}_lustre.${_ARCH}
    OFED_SRC_DIR=/usr/src/ofa_kernel/$_ARCH}/${_KERNEL_VER}.el${_EL_MAJ_VER}_lustre.${_ARCH}/
  else
    KERNEL_NAME=${_KVER}/linux-${_KERNEL_VER}_lustre.el${_EL_MAJ_VER}.${_ARCH}
    OFED_SRC_DIR=/usr/src/ofa_kernel/$_ARCH}/${_KERNEL_VER}_lustre.el${_EL_MAJ_VER}.${_ARCH}/
  fi

  cd $_WORK_DIR/lustre-release
  echo ./configure --with-linux=$_WORK_DIR/kernel/rpmbuild/BUILD/kernel-${KERNEL_NAME} --enable-server --with-o2ib=$OFED_SRC_DIR
  ./configure --with-linux=$_WORK_DIR/kernel/rpmbuild/BUILD/kernel-${KERNEL_NAME} --enable-server --with-o2ib=$OFED_SRC_DIR
  make rpms
  cp -v $_WORK_DIR/lustre-release/*.rpm $_RPM_DIR
}

function usage () {
echo "Usage: $0 -r <RPM_output_dir> -w <working_dir>"
echo "          -l <lustre_version> -o <ofed_version>"
echo "          -k <kernel_version> -E <e2fs_version>"
echo "          -e <EL_version> -a <architecture>"
exit 255
}

#main
WORK_DIR=/dev/shm
RPM_DIR=/rpms
E2FS_VER=latest
DOCA_URL="https://linux.mellanox.com/public/repo/doca/"
LUSTRE_URL="git://git.whamcloud.com/fs/lustre-release.git"
_ARCH=x86_64
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
        E)
            E2FS_VER=${OPTARG}
            ;;
        e)
            EL_VER=${OPTARG}
            ;;
        a)
            _ARCH=${OPTARG}
            ;;
        L)
            LUSTRE_URL=${OPTARG}
            ;;
        K)
            KERNEL_URL=${OPTARG}
            ;;
        D)
            DOCA_URL=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done

echo "-w $WORK_DIR -r $RPM_DIR -l $LUSTRE_VER -k $KERNEL_VER -o $OFED_VER -e $EL_VER -E $E2FS_VER -a $_ARCH"
mkdir -p $RPM_DIR

install_dependencies $EL_VER $_ARCH $E2FS_VER $RPM_DIR
clone_lustre_source $WORK_DIR $LUSTRE_VER $LUSTRE_URL
install_doca $WORK_DIR $EL_VER $DOCA_VER $RPM_DIR $DOCA_URL
compile_kernel $WORK_DIR $EL_VER $KERNEL_VER $_ARCH $RPM_DIR
compile_lustre $WORK_DIR $EL_VER $KERNEL_VER $_ARCH $RPM_DIR
