# start-avm

A utility to easily run Android Cuttlefish VMs with QEMU.

## Building

Simply running `make` should do the trick. No special dependencies are required.

``` sh
cd ~/start-avm
make
```

## Using

### Setting up the Cuttlefish Directory

1. Download a cuttlefish image from
[http://ci.android.com/](http://ci.android.com/). If you don't exactly what to
download, read [this guide](https://source.android.com/docs/setup/create/cuttlefish-use).

2. Create a directory and unpack for the cuttlefish images and the CVD tools.

``` sh
mkdir cuttlefish
cd cuttlefish
unzip ~/Downloads/aosp_cf_x86_64_phone-img*.zip
tar xf ~/Downloads/cvd-host_package.tar.gz
```

3. Create a directory to hold the QEMU images and support files, and use
   [cvd2img](https://github.com/slp/cvd2img) to generate the images.
   
``` sh
mkdir qemu
cd qemu
cvd2img ..
```

### Starting the VM

1. Go to the directory containing the `start-avm` repository.

``` sh
cd ~/start-avm
```
   
2. On a terminal with access to the graphics server, run `start_avm.sh`
   pointing to the cuttlefish directory.
   
``` sh
./start_avm.sh ~/cuttlefish
```

A QEMU window will appear, and in a few seconds the Android boot animation
should show up.
