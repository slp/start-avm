#!/bin/bash

OPTIONS="-u"

if [ "$VIRGL" == 1 ]; then
	OPTIONS="$OPTIONS -v"
fi

if [ "$MULTITOUCH" == 1 ]; then
	OPTIONS="$OPTIONS -m"
fi

if [ ! -d /android ]; then
	echo "Missing android directory"
	exit -1
fi

if [ ! -e /android/super.img ]; then
	echo "Missing CVD images"
	exit -1
fi

if [ ! -d /android/qemu ]; then
	mkdir /android/qemu
	cd /android/qemu
	cvd2img ..
fi

/opt/start-avm/start_avm.sh $OPTIONS /android

