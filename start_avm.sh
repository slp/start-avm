#!/usr/bin/env bash

CONFIG_SERVER=0
VHOST_USER=0
VHOST_VIDEO=0
DRM=0
MT=0
DEBUG=0
ROTARY=0
MODE=AUTO
QEMU_PATH=""

function print_usage {
    echo "Usage: $0 [OPTIONS] <ANDROID_BASE_DIR>"
    echo "Options:"
    echo "  -r                       Use the real config_server instead of a stub"
    echo "  -u                       Use vhost-user-vsock instead of vhost-vsock"
    echo "  -v                       Enable virgl GPU acceleration"
    echo "  -d                       Display debug messages and commands as they are executed"
    echo "  --mt                     Use virtio-multitouch as input device"
    echo "  --video                  Enable vhost-user-video device (experimental)"
    echo "  --rotary                 Add virtio-rotary as input device"
    echo "  -m,--mode [PHONE|AUTO]   Use Android Phone/Automotive display settings (default: AUTO)"
    echo "  -q,--qemu                Path to the Qemu build folder instead of the automatic search"
    exit -1
}

options=$(getopt -o ruvm:dhq: --long help,mt,mode:,qemu:,video,rotary -n "$0" -- "$@")
if [ "$?" != 0 ]; then
    print_usage
fi
eval set -- "${options}"

while :; do
    case "${1}" in
        -r)
            CONFIG_SERVER=1
            ;;
        -u)
            VHOST_USER=1
            ;;
        --video)
            VHOST_VIDEO=1
            ;;
        -v)
            DRM=1
            ;;
        --mt)
            MT=1
            ;;
        --rotary)
            ROTARY=1
            ;;
        -d)
            DEBUG=1
            ;;
        -h | --help)
            print_usage
            ;;
        -m | --mode)
            MODE=${2^^}
            if [ $MODE != "PHONE" -a $MODE != "AUTO" ]; then
                echo "Error: Invalid mode (${MODE})"
                print_usage
            fi
            shift
            ;;
        -q | --qemu)
            QEMU_PATH=$2
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
    shift
done

if [ -z "$1" ]; then
    echo "Error: Missing mandatory fields"
    print_usage
fi

[ $DEBUG == 1 ] && set -x

CVD_BASE_DIR=${@:$OPTIND:1}

if [ -z "${CVD_BASE_DIR}" ]; then
    print_usage
elif [ ! -e ${CVD_BASE_DIR} ]; then
    echo "Directory ${CVD_BASE_DIR} doesn't exist or can't be accessed"
    exit -1
fi

CVD_TOOLS_OPTS=""
if [ $CONFIG_SERVER == 1 ]; then
    CVD_TOOLS_OPTS="-r"
    NETWORK="-netdev tap,id=hostnet0,ifname=cvd-mtap-01,script=no,downscript=no"
else
    NETWORK="-netdev user,id=hostnet0"
fi
if [ $VHOST_USER == 1 ]; then
    VSOCK_PATH="/usr/bin/vhost-user-vsock"
    if [ ! -f "$VSOCK_PATH" ]; then
        echo "ERROR: vhost-user-vsock binary not found"
        exit 1
    fi
    $VSOCK_PATH --socket ${CVD_BASE_DIR}/qemu/vhost-user-vsock.sock --uds-path ${CVD_BASE_DIR}/qemu/vhost-user-vsock.uds &
    CVD_TOOLS_OPTS="$CVD_TOOLS_OPTS -u"
    VSOCK="-chardev socket,id=char0,reconnect=0,path=${CVD_BASE_DIR}/qemu/vhost-user-vsock.sock -device vhost-user-vsock-pci,chardev=char0"
else
    VSOCK="-device vhost-vsock-pci-non-transitional,guest-cid=3"
fi
if [ $VHOST_VIDEO == 1 ]; then
    # Adds video device to Qemu command line, the vhost backend must be run separately
    # The 'vhost-user-video-pci' device only exists in out-of-tree Qemu
    VIDEO="  -device vhost-user-video-pci,chardev=video,id=video \
  -chardev socket,path=/tmp/video.sock,id=video"
fi

AVM_BASE_DIR=`dirname $0`
$AVM_BASE_DIR/start_cvd_tools $CVD_TOOLS_OPTS $CVD_BASE_DIR &
TOOLS_PID=$!

if [ ! -e ${CVD_BASE_DIR}/.cuttlefish_config.json ]; then
    echo "Generating cuttlefish config and directories"
    sed -e "s@CVDBASEDIR@${CVD_BASE_DIR}@" $AVM_BASE_DIR/templates/.cuttlefish_config.json > $CVD_BASE_DIR/.cuttlefish_config.json
    mkdir -p ${CVD_BASE_DIR}/cuttlefish/instances/cvd-1/logs
    mkdir -p ${CVD_BASE_DIR}/cuttlefish/instances/cvd-1/internal
fi

ARCH=`uname -m`
if [ $ARCH == "x86_64" ]; then
    MACHINE="pc"
else
    MACHINE="virt"
fi

QEMU=/usr/libexec/qemu-kvm
if [ ! -z "$QEMU_PATH" ]; then
    QEMU="${QEMU_PATH}/qemu-system-${ARCH}"
fi
if [ ! -x ${QEMU} ]; then
    QEMU=qemu-system-${ARCH}
fi

if ${QEMU} -display ? | grep -q dbus; then
    UI="dbus"
elif ${QEMU} -display ? | grep -q gtk; then
    UI="gtk"
else
    UI="egl-headless -vnc :0"
fi

if [ $MODE = "PHONE" ]; then
    GPU_DEV_OPTS="xres=720,yres=1280"
else
    GPU_DEV_OPTS="xres=2560,yres=1440,max_outputs=2"
fi

if [ $DRM == 1 ]; then
    DRM_SOCKET=/tmp/vgpu.sock
    CHARDEV_ID=vgpu
    GPU_DEV_OPTS="${GPU_DEV_OPTS},chardev=${CHARDEV_ID}"
    VHOST_GPU_PATH=/usr/libexec
    if [ ! -z "$QEMU_PATH" ]; then
        VHOST_GPU_PATH="${QEMU_PATH}/contrib/vhost-user-gpu"
    fi
    ${VHOST_GPU_PATH}/vhost-user-gpu -s /tmp/vgpu.sock -v &
    GPU=" -display ${UI},gl=on -nodefaults -no-user-config \
 -chardev socket,id=${CHARDEV_ID},path=${DRM_SOCKET} \
 -device vhost-user-gpu-pci,${GPU_DEV_OPTS}"
    PROPERTIES="properties_virgl.img"
else
    GPU=" -display ${UI} -nodefaults -no-user-config \
 -device virtio-gpu-pci,${GPU_DEV_OPTS}"
    PROPERTIES="properties.img"
fi

if [ $MT == 1 ]; then
    INPUT="virtio-multitouch-pci"
else
    INPUT="virtio-mouse-pci"
fi

if [ $ROTARY == 1 ]; then
    ROTARY_INPUT="-device virtio-rotary-pci,disable-legacy=on"
fi

if ${QEMU} -device ? | grep -q AC97; then
    AUDIO="-device AC97"
else
    AUDIO="-device ich9-intel-hda"
fi
if ${QEMU} -audio ? | grep -q pipewire; then
    AUDIO="${AUDIO} -audio pipewire"
else
    AUDIO="${AUDIO} -audio none"
fi

${QEMU} -name guest=cvd-1,debug-threads=on \
 -machine $MACHINE,nvdimm=on,accel=kvm,usb=off,dump-guest-core=off \
 -object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem \
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
 -chardev pipe,id=hvc10,path=${CVD_BASE_DIR}/qemu/oemlock_fifo_vm \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial10 \
 -device virtconsole,bus=virtio-serial10.0,chardev=hvc10 \
 -chardev pipe,id=hvc11,path=${CVD_BASE_DIR}/qemu/keymint_fifo_vm \
 -device virtio-serial-pci-non-transitional,max_ports=1,id=virtio-serial11 \
 -device virtconsole,bus=virtio-serial11.0,chardev=hvc11 \
 -drive file=${CVD_BASE_DIR}/qemu/system.img,format=raw,snapshot=on,if=none,id=drive-virtio-disk0,aio=threads \
 -device virtio-blk-pci-non-transitional,scsi=off,drive=drive-virtio-disk0,id=virtio-disk0,bootindex=1 \
 -drive file=${CVD_BASE_DIR}/qemu/${PROPERTIES},format=raw,snapshot=on,if=none,id=drive-virtio-disk1,aio=threads \
 -device virtio-blk-pci-non-transitional,scsi=off,drive=drive-virtio-disk1,id=virtio-disk1 \
 -object rng-random,id=objrng0,filename=/dev/urandom \
 -device virtio-rng-pci-non-transitional,rng=objrng0,id=rng0,max-bytes=1024,period=2000 \
 -device ${INPUT},disable-legacy=on \
 -device virtio-keyboard-pci,disable-legacy=on \
 -device virtio-balloon-pci-non-transitional,id=balloon0 \
 $ROTARY_INPUT \
 $NETWORK \
 -device virtio-net-pci-non-transitional,netdev=hostnet0,id=net0,mac=00:1a:11:e0:cf:00 \
 -cpu host -msg timestamp=on \
 $VSOCK \
 $AUDIO \
 $VIDEO \
 -device qemu-xhci,id=xhci \
 -bios ${CVD_BASE_DIR}/etc/bootloader_${ARCH}/bootloader.qemu

kill $TOOLS_PID
