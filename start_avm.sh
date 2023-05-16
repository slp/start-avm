#!/bin/bash

DRM=0

if [ $# == 1 ]; then
    CVD_BASE_DIR=$1
elif [ $# == 2 ]; then
    if [ $1 == "--drm" ]; then
        DRM=1
    else
        echo "Invalid option"
        exit
    fi
    CVD_BASE_DIR=$2
else
    echo "Usage: $0 [--drm] ANDROID_BASE_DIR"
    exit
fi

AVM_BASE_DIR=`dirname $0`
$AVM_BASE_DIR/start_cvd_tools $CVD_BASE_DIR &
TOOLS_PID=$!

if [ ! -e ${CVD_BASE_DIR}/.cuttlefish_config.json ]; then
    echo "Generating cuttlefish config and directories"
    sed -e "s@CVDBASEDIR@${CVD_BASE_DIR}@" $AVM_BASE_DIR/templates/.cuttlefish_config.json > $CVD_BASE_DIR/.cuttlefish_config.json
    mkdir -p ${CVD_BASE_DIR}/cuttlefish/instances/cvd-1/logs
    mkdir -p ${CVD_BASE_DIR}/cuttlefish/instances/cvd-1/internal
fi

if [ $DRM == 1 ]; then
    /usr/libexec/vhost-user-gpu -s /tmp/vgpu.sock -v &
    GPU=" -object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem \
 -display gtk,gl=on -nodefaults -no-user-config \
 -chardev socket,id=vgpu,path=/tmp/vgpu.sock \
 -device vhost-user-gpu-pci,chardev=vgpu"
    PROPERTIES="properties_virgl.img"
else
    GPU=" -display gtk -nodefaults -no-user-config \
 -device virtio-gpu-pci,xres=720,yres=1280"
    PROPERTIES="properties.img"
fi

ARCH=`uname -m`
if [ $ARCH == "x86_64" ]; then
    MACHINE="pc"
else
    MACHINE="virt"
fi

qemu-system-${ARCH} -name guest=cvd-1,debug-threads=on \
 -machine $MACHINE,nvdimm=on,accel=kvm,usb=off,dump-guest-core=off \
 -m size=4096M,maxmem=4102M,slots=2 -overcommit mem-lock=off -smp 2,cores=2,threads=1 \
 -no-user-config -nodefaults -no-shutdown -rtc base=utc -boot strict=on \
 $GPU \
 -chardev file,id=serial0,path=${CVD_BASE_DIR}/qemu/kernel-log-pipe,append=on \
 -serial chardev:serial0 \
 -chardev file,id=hvc0,path=${CVD_BASE_DIR}/qemu/kernel-log-pipe,append=on \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial0 \
 -device virtconsole,bus=virtio-serial0.0,chardev=hvc0 \
 -chardev null,id=hvc1 \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial1 \
 -device virtconsole,bus=virtio-serial1.0,chardev=hvc1 \
 -chardev file,id=hvc2,path=${CVD_BASE_DIR}/qemu/logcat-pipe,append=on \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial2 \
 -device virtconsole,bus=virtio-serial2.0,chardev=hvc2 \
 -chardev pipe,id=hvc3,path=${CVD_BASE_DIR}/qemu/keymaster_fifo_vm \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial3 \
 -device virtconsole,bus=virtio-serial3.0,chardev=hvc3 \
 -chardev pipe,id=hvc4,path=${CVD_BASE_DIR}/qemu/gatekeeper_fifo_vm \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial4 \
 -device virtconsole,bus=virtio-serial4.0,chardev=hvc4 \
 -chardev pipe,id=hvc5,path=${CVD_BASE_DIR}/qemu/bt_fifo_vm \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial5 \
 -device virtconsole,bus=virtio-serial5.0,chardev=hvc5 \
 -chardev null,id=hvc6 \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial6 \
 -device virtconsole,bus=virtio-serial6.0,chardev=hvc6 \
 -chardev null,id=hvc7 \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial7 \
 -device virtconsole,bus=virtio-serial7.0,chardev=hvc7 \
 -chardev null,id=hvc8 \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial8 \
 -device virtconsole,bus=virtio-serial8.0,chardev=hvc8 \
 -chardev null,id=hvc9 \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial9 \
 -device virtconsole,bus=virtio-serial9.0,chardev=hvc9 \
 -drive file=${CVD_BASE_DIR}/qemu/system.img,format=raw,snapshot=on,if=none,id=drive-virtio-disk0,aio=threads \
 -device virtio-blk-pci-non-transitional,scsi=off,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 \
 -drive file=${CVD_BASE_DIR}/qemu/${PROPERTIES},format=raw,snapshot=on,if=none,id=drive-virtio-disk1,aio=threads \
 -device virtio-blk-pci-non-transitional,scsi=off,drive=drive-virtio-disk1,id=virtio-disk1 \
 -object rng-random,id=objrng0,filename=/dev/urandom \
 -device virtio-rng-pci-non-transitional,rng=objrng0,id=rng0,max-bytes=1024,period=2000 \
 -device virtio-mouse-pci,disable-legacy=on \
 -device virtio-keyboard-pci,disable-legacy=on \
 -device virtio-keyboard-pci,disable-legacy=on \
 -device virtio-balloon-pci-non-transitional,id=balloon0 \
 -netdev tap,id=hostnet0,ifname=cvd-mtap-01,script=no,downscript=no \
 -device virtio-net-pci-non-transitional,netdev=hostnet0,id=net0,mac=00:1a:11:e0:cf:00 \
 -cpu host -msg timestamp=on \
 -device vhost-vsock-pci-non-transitional,guest-cid=3 \
 -device AC97 -device qemu-xhci,id=xhci \
 -bios ${CVD_BASE_DIR}/etc/bootloader_${ARCH}/bootloader.qemu

kill $TOOLS_PID
