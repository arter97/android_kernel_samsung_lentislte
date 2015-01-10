#!/bin/bash
export KERNELDIR=`readlink -f .`
export RAMFS_SOURCE=`readlink -f $KERNELDIR/ramdisk`
export USE_SEC_FIPS_MODE=true

echo "kerneldir = $KERNELDIR"
echo "ramfs_source = $RAMFS_SOURCE"

RAMFS_TMP="/tmp/arter97-g906s-ramdisk"

echo "ramfs_tmp = $RAMFS_TMP"
cd $KERNELDIR

if [ "${1}" = "skip" ] ; then
	echo "Skipping Compilation"
else
	echo "Compiling kernel"
	cp defconfig .config
	make "$@" || exit 1
fi

echo "Building new ramdisk"
#remove previous ramfs files
rm -rf '$RAMFS_TMP'*
rm -rf $RAMFS_TMP
rm -rf $RAMFS_TMP.cpio
#copy ramfs files to tmp directory
cp -ax $RAMFS_SOURCE $RAMFS_TMP
cd $RAMFS_TMP

find . -name '*.sh' -exec chmod 755 {} \;

$KERNELDIR/ramdisk_fix_permissions.sh 2>/dev/null

#clear git repositories in ramfs
find . -name .git -exec rm -rf {} \;
find . -name EMPTY_DIRECTORY -exec rm -rf {} \;
cd $KERNELDIR
rm -rf $RAMFS_TMP/tmp/*

cd $RAMFS_TMP
find . | fakeroot cpio -H newc -o | gzip -9 > $RAMFS_TMP.cpio.gz
ls -lh $RAMFS_TMP.cpio.gz
cd $KERNELDIR

echo "Making new boot image"
gcc -w -s -pipe -O2 -o tools/dtbtool/dtbtool tools/dtbtool/dtbtool.c
tools/dtbtool/dtbtool -s 2048 -o arch/arm/boot/dt.img -p scripts/dtc/ arch/arm/boot/dts/
gcc -w -s -pipe -O2 -Itools/libmincrypt -o tools/mkbootimg/mkbootimg tools/libmincrypt/*.c tools/mkbootimg/mkbootimg.c
tools/mkbootimg/mkbootimg --kernel $KERNELDIR/arch/arm/boot/zImage --dt $KERNELDIR/arch/arm/boot/dt.img --ramdisk $RAMFS_TMP.cpio.gz --cmdline 'console=null androidboot.hardware=qcom msm_rtb.filter=0x37 dwc3_msm.cpu_to_affin=1 androidboot.selinux=permissive enforcing=0' --base 0x00000000 --pagesize 4096 --kernel_offset 0x00008000 --ramdisk_offset 0x02600000 --tags_offset 0x02400000 --second_offset 0x00f00000 -o $KERNELDIR/boot.img
echo -n "SEANDROIDENFORCE" >> boot.img
if [ "${1}" = "CC=\$(CROSS_COMPILE)gcc" ] ; then
	dd if=/dev/zero bs=$((13631488-$(stat -c %s boot.img))) count=1 >> boot.img
fi

echo "done"
ls -al boot.img
echo ""
