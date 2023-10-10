#!/usr/bin/env bash

VIRGL=0
MT=0

function print_usage {
    echo "Usage: $0 [OPTIONS] <ANDROID_BASE_DIR>"
    echo "Options:"
    echo "  -v          Enable virgl GPU acceleration"
    echo "  -m          Use virtio-multitouch as input device"
    exit -1
}

while getopts ":vm" options; do
    case "${options}" in
        v)
            VIRGL=1
            ;;
        m)
            MT=1
            ;;
        :)
            echo "Error: -${OPTARG} requires an argument."
            print_usage
            ;;
        *)
            print_usage
            ;;
    esac
done

CVD_BASE_DIR=${@:$OPTIND:1}

if [ -z "${CVD_BASE_DIR}" ]; then
    print_usage
elif [ ! -e ${CVD_BASE_DIR} ]; then
    echo "Directory ${CVD_BASE_DIR} doesn't exist or can't be accessed"
    exit -1
fi

if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ]; then
    echo "Can't find WAYLAND_DISPLAY or DISPLAY in this session"
    exit -1
fi

ENVS=""
if [ $VIRGL == 1 ]; then
    ENVS="$ENVS -e VIRGL=1"
fi
if [ $MT == 1 ]; then
    ENVS="$ENVS -e MULTITOUCH=1"
fi

podman run -ti --rm --privileged \
 \
 --device /dev/kvm \
 --device /dev/dri/renderD128 \
 \
 -v $CVD_BASE_DIR:/android:z \
 \
 -v /run/user/1000/:/run/user/1000/ \
 $ENVS \
 -e XDG_RUNTIME_DIR=/run/user/1000 \
 -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
 -e DISPLAY="$DISPLAY" \
 -e PULSE_SERVER=/run/user/1000/pulse/native \
 \
 --shm-size=5g \
 \
 quay.io/slopezpa/qemu-android
