#!/bin/bash

NFS_FILE="
    /mydata/some-tutorials
    /mydata/linux/arch/x86/boot/bzImage
    /mydata/edk2-sev/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd
    /mydata/edk2-sev/Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd
    /mydata/some-tutorials/files/amd-sev/ramdisk.img
"

MYDATA_FILE="
    /mydata/qemu-sev
    /mydata/qemu
"

for file in $NFS_FILE
do
    rsync --progress -avrzh $file /mydata/nfs/
done

for file in $MYDATA_FILE
do
    rsync --progress -avrzh $file 10.10.1.1:/mydata
    rsync --progress -avrzh $file 10.10.1.2:/mydata
done

sudo chmod 777 /mydata/nfs/*
