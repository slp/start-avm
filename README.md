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

### Option 1: Starting the VM directly on host

1. Go to the directory containing the `start-avm` repository.

``` sh
cd ~/start-avm
```
   
2. On a terminal with access to the graphics server, run `start_avm.sh`
   pointing to the cuttlefish directory.
   
``` sh
./start_avm.sh ~/cuttlefish
```

### Option 2: Starting the VM as a container with podman

1. Go to the directory containing the `start-avm` repository.

``` sh
cd ~/start-avm
```

2. On a terminal with access to the graphics server, run `run_podman.sh`
   pointing to the cuttlefish directory.

``` sh
./run_podman.sh ~/cuttlefish
```

### Using virgl acceleration and multi-touch support

If you're on a device with hardware capable of generating multi-touch
events, you can enable both multi-touch support and virgl acceleration
(which depends on multi-touch support due to cuttlefish limitations) by
passing the `-m` and `-v` options to either `start_avm.sh` or
`run_podman.sh`.

## Troubleshooting

### Broken config file

If you get messages about syntax errors in `.cuttlefish_config.json` config file then:

- Remove the file.
- Run start\_avm.sh (or run\_podman.sh) twice.

### Outdated container image

If run\_podman.sh doesn't work, it may be because of an outdated container image on Quay.
To rebuild the image locally, run:

```
podman build -t qemu-android .
```

in `start-avm` directory.
