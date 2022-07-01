#
# Tainer ToolKit V2
#

export VERSION=2.0.0.001
# 运行时环境目录
export TOOLKIT_XBIN=

#
# FileSystem
#
fsbind_chroot_init(){
if [ -e "$ROOTFS/proc/version" ];then
  echo >/dev/null
else
  mount -t proc proc $ROOTFS/proc
  mount -t sysfs sysfs $ROOTFS/sys
  mount -t devpts devpts $ROOTFS/dev/pts
fi
}
fsbind_proot_init(){
# inject proot start command.
export ADDCMD=" $ADDCMD -b /dev -b /proc -b /sys -b /root:/dev/shm"
}

#
# Environment Check
#
check_platform(){
# get arch type from getprop
arch=$(getprop ro.product.cpu.abi)
case "${arch}" in
arm64-v8a|arm64|armv8l)
    echo "aa64"
;;
armeabi-v7a|armeabi|arm*)
    echo "arm"
;;
x86_64|amd64)
    echo "x64"
;;
*)
    echo "unknown"
;;
esac
}

check_engine_status(){
if [[ "$(cat $ROOTFS/.tainer/status)" = "1" ]];then
  echo "Error: The container is running, the current operation cannot be start, please stop the container first"
  exit
fi
}

check_rootfs(){
if [ ! -d "$ROOTFS" ];then
  echo "Error: Can't mount container's rootfs, so can't work normally."
  exit
fi
}

check_nspawn_support(){
if [[ "$(unshare -f --mount --uts --ipc --pid --mount-proc echo 1)" != "1" ]];then
  echo "Error: Kernel doesn't support UTS,IPC,PID namespace,and nspawn engine can't work."
  exit
fi
}

check_binfmtmisc_support(){
if [ ! -e "/proc/sys/fs/binfmt_misc/register" ];then
   echo "Error: Can't find register,and qemu emulator can't work with chroot."
   exit 9
fi
}

#
# Deployment
#
deploy_rootfs_targz(){
# enter first stage
deploy_common_1st
# create rootfs space
deploy_rootfs_common
# enbale link2symLink for proot
if [ `id -u` -eq 0 ];then
  TARCMD="$TOOLKIT_XBIN/busybox tar -xzf $file -C $cached_rootfs"
else
  TARCMD="$TOOLKIT_XBIN/proot --link2symlink -0 $TOOLKIT_XBIN/busybox tar --no-same-owner -xzf $file -C $cached_rootfs"
fi
# exec tar command
$TARCMD
unset TARCMD
# enter next stage
deploy_common_2nd
}

deploy_rootfs_tarxz(){
# enter first stage
deploy_common_1st
# create rootfs space
deploy_rootfs_common
# enbale link2symLink for proot
if [ `id -u` -eq 0 ];then
  TARCMD="$TOOLKIT_XBIN/busybox tar -xJf $file -C $cached_rootfs"
else
  TARCMD="$TOOLKIT_XBIN/proot --link2symlink -0 $TOOLKIT_XBIN/busybox tar --no-same-owner -xJf $file -C $cached_rootfs"
fi
# exec tar command
$TARCMD
unset TARCMD
# enter next stage
deploy_common_2nd
}

deploy_rootfs_common(){
echo "- Installing rootfs"
rm -rf $cached_rootfs
mkdir -p $cached_rootfs
}

#
# First-Stage Deploy
#
deploy_common_1st(){
# init proot env
export PROOT_TMP_DIR="$TMPDIR"
export PROOT_LOADER="$TOOLKIT/lib/libloader.so"
if [[ "$platform" = "x64" ]] && [[ "$platform" = "aa64" ]];then
  export PROOT_LOADER_32="$TOOLKIT/lib/libloader32.so"
fi
echo "progress:[1/10]"
# Check configs available
if [ ! -n "$cached_rootfs" ];then
  echo "Error: The selected path is not available"
  exit 9
fi
if [ ! -n "$file" ];then
  echo "Error: The selected rootfs file is not available"
  exit 9
fi
# Install to App Internal Storage(non-root mode)
if [[ "$install_app_internal" = "1" ]];then
  engine_common_proot
  export cached_rootfs="$START_DIR/$cached_rootfs/"
  echo "Non-Root Mode: Rootfs will install to $cached_rootfs"
fi
echo "progress:[3/10]"
}

#
# Second Stage Deploy
#

# Rootfs Custom Options:
# rootfs_package/TainerConfig/engine_cmdline.config : custom rootfs start cmdline
# rootfs_package/TainerConfig/exec_after_install.sh : this shell script will exec after install rootfs
#
deploy_common_2nd(){
if [ ! -d "$cached_rootfs/bin/" ];then
  echo "Error: An exception occurred during the decompression process"
  exit 255
fi
echo "progress:[6/10]"
echo "- Configuring"
# Setup app config data
if [ -d "$cached_rootfs/TainerConfig/" ];then
  # get preloaded config from package
  cat $cached_rootfs/TainerConfig/engine_cmdline.config>$CONFIG_DIR/engine_cmdline.config
  echo "$cached_rootfs" >$CONFIG_DIR/engine_rootfs.config
  # exec custom setup
  . $cached_rootfs/TainerConfig/exec_after_install.sh
  # clean up
  rm -rf $cached_rootfs/TainerConfig
else
  # use empty config
  echo "$cached_rootfs" >$CONFIG_DIR/engine_rootfs.config
fi
# init TainerConfig
mkdir $cached_rootfs/.tainer
echo "0">$cached_rootfs/.tainer/status
echo "DO NOT REMOVE THIS FILE,OR YOU WILL LOST ALL DATA!">$cached_rootfs/.tainer/.installed_rootfs
# create rootfs mountpoints
mkdir -p $cached_rootfs/{sys,dev,proc,dev/pts,dev/shm}
# Run DistroTool
. $TOOLKIT_XBIN/app-addon/distrotool.sh main
echo "!All Done"
}

deploy_remove_rootfs(){
if [[ "$AGREEMENT" != "1" ]];then
  echo "Error: failed to remove rootfs"
  exit 9
fi

if [ -e "$ROOTFS/.tainer/.installed_rootfs" ];then
  check_rootfs_status
  echo "- Removing"

  if [ `id -u` -eq 0 ];then
     rm -rf $ROOTFS
  else
    # load proot to fakeroot
    export PROOT_TMP_DIR="$TMPDIR"
    export PROOT_LOADER="$TOOLKIT/lib/libloader.so"
    if [[ "$platform" = "x64" ]] && [[ "$platform" = "aa64" ]];then
      export PROOT_LOADER_32="$TOOLKIT/lib/libloader32.so"
    fi
    $TOOLKIT_XBIN/proot -0 $TOOLKIT_XBIN/busybox rm -rf $ROOTFS
  fi

  # Clean Configs
  echo >$CONFIG_DIR/engine_rootfs.config
  echo >$CONFIG_DIR/engine_cmdline.config
  echo "- All Done"
  else
  echo "Error: failed to remove rootfs"
fi
}

deploy_backup_rootfs(){
if [ ! -n "$dir" ];then
  echo "!The selected path is not available"
  exit 1
fi
check_rootfs_status
echo "- Backuping rootfs"
cd $ROOTFS/
# make sure to switch to rootfs dir correctly!
if [[ "$(pwd)" != "/" ]];then
  # set backup method
  if [ `id -u` -eq 0 ];then
      TARCMD="$TOOLKIT_XBIN/busybox tar czf "$dir/backup.tar.gz" --exclude='./dev' --exclude='./sys' --exclude='./proc' ./"
  else
      # init proot to fakeroot
      export PROOT_TMP_DIR="$TMPDIR"
      export PROOT_LOADER="$TOOLKIT/lib/libloader.so"
      if [[ "$platform" = "x64" ]] && [[ "$platform" = "aa64" ]];then
        export PROOT_LOADER_32="$TOOLKIT/lib/libloader32.so"
      fi
      TARCMD="$TOOLKIT_XBIN/proot --link2symlink -0 $TOOLKIT_XBIN/busybox tar czf "$dir/backup.tar.gz" --exclude='./dev' --exclude='./sys' --exclude='./proc' ./"
  fi
  # exec tar command
  $TARCMD
  echo "Saved to $dir/backup.tar.gz"
else
  echo "Error: can't backup rootfs"
  exit
fi
# the end
echo "- All done"
}

#
# Engine
#
exec_localshell(){
if [[ "$boxenv" = "1" ]];then
  echo "NOTE: local-shell doesn't support sandbox Mode!"
fi
$cmd2
}

#
# Engine Common Setup
#
engine_common_proot(){
export PROOT_TMP_DIR="$TMPDIR"
export PROOT_LOADER="$TOOLKIT/lib/libloader.so"
if [[ "$platform" = "x64" ]] && [[ "$platform" = "aa64" ]];then
  export PROOT_LOADER_32="$TOOLKIT/lib/libloader32.so"
fi
# enable proot debug
if [ -e "$CONFIG_DIR/.debug" ];then
  export ADDCMD="$ADDCMD -v $(cat $CONFIG_DIR/.debug)"
fi 
# enable qemu emulator
if [ -f "$CONFIG_DIR/.qemu" ];then
  export qemu="$TOOLKIT_XBIN/qemu-user-$(cat $CONFIG_DIR/.qemu)"
  export ADDCMD="$ADDCMD -q $qemu"
fi
}

# Auto Select
engine_exec_auto(){
check_rootfs 
if [ "$(id -u)" = "0" ];then
	exec_unshare
else
	exec_proot
fi
}

engine_start_auto(){
if [ "$(id -u)" = "0" ];then
	start_unshare
else
	start_proot
fi
}

# Engine Exec
engine_exec_nspawn(){
echo "progress:[1/1]"
check_rootfs
check_nspawn_support
set_env
init_boxenv
exec $TOOLKIT_XBIN/unshare $ADDCMD -f --mount --uts --ipc --pid --mount-proc  $TOOLKIT_XBIN/chroot $ROOTFS /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/games:/usr/local/games:/usr/local/sbin:/sbin $cmd2
}

engine_exec_proot(){
echo "progress:[1/1]"
engine_common_proot
set_env
fsbind_proot_init
startcmd=" $ADDCMD --kill-on-exit -0 --link2symlink --sysvipc -r $ROOTFS "
startcmd=" $startcmd -w /root $cmd2"
exec $TOOLKIT_XBIN/proot $startcmd
}

engine_exec_chroot(){
echo "progress:[1/1]"
check_rootfs
init_boxenv
fsbind_unshare_init
set_env
exec $TOOLKIT_XBIN/chroot $ROOTFS /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/games:/usr/local/games:/usr/local/sbin:/sbin $cmd2
}

# Engine Starter
engine_start_nspawn(){
echo "progress:[1/1]"
check_rootfs
# Check RunStatus
if [[ "$(cat $ROOTFS/.tainer/status)" != "0" ]];then
  engine_killall
else
  echo "- Starting"
  check_nspawn_support
  init_boxenv
  set_env
  echo "1">$ROOTFS/.tainer/status
  exec $TOOLKIT_XBIN/unshare $ADDCMD -f --mount --uts --ipc --pid --mount-proc $TOOLKIT_XBIN/chroot $ROOTFS $cmd
fi
}

engine_start_proot(){
echo "progress:[1/1]"
check_rootfs
if [[ "$(cat $ROOTFS/.tainer/status)" != "0" ]];then
  engine_killall
else
  init_boxenv
  engine_common_proot
  echo "- Starting"
  fsbind_proot_init
  set_env
  startcmd=" $ADDCMD -0 --link2symlink --sysvipc -r $ROOTFS "
  startcmd+="-w /root $cmd"
  echo "1">$ROOTFS/.tainer/status
  exec $TOOLKIT_XBIN/proot $startcmd
fi
}

engine_start_chroot(){
echo "progress:[1/1]"
check_rootfs
# Check RunStatus
if [[ "$(cat $ROOTFS/.tainer/status)" != "0" ]];then
  engine_killall
else
  echo "- Starting"
  init_boxenv
  fsbind_unshare_init
  set_env
  echo "1">$ROOTFS/.tainer/status
  exec $TOOLKIT_XBIN/chroot $ADDCMD $ROOTFS $cmd
fi
}
# Engine Killer
engine_killall(){
if [[ "$(cat $ROOTFS/.tainer/status)" = "1" ]];then
  killall -9 dropbear sshd
  if [ -e "$ROOTFS/proc/version" ];then
    umount -f -l $ROOTFS/proc
    umount -f -l $ROOTFS/dev/pts
    umount -f -l $ROOTFS/dev
    umount -f -l $ROOTFS/sys
  else
    echo >/dev/null
  fi
  echo "0">$ROOTFS/.tainer/status
  killall -9 bash unshare proot
  killall -9 $PACKAGE_NAME
fi
}

#
# Sandbox Mode
#
init_boxenv(){
if [[ -d "$TMPDIR/boxenv" ]];then
rm -rf $TMPDIR/boxenv
fi
if [[ "$boxenv" = "1" ]];then
echo "- Starting Sandbox mode"
mkdir $TMPDIR/boxenv
if [ `id -u` -eq 0 ];then
  cp -R $ROOTFS/* $TMPDIR/boxenv
else
  proot --link2symlink -0 cp -R $ROOTFS/* $TMPDIR/boxenv
fi
echo "0">$TMPDIR/boxenv/.tainer/status
unset ROOTFS
export ROOTFS="$TMPDIR/boxenv"
fi
}
