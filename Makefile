KERNEL = linux-2.6.14
QEMU   = qemu-0.15.0
DNS_FW = dns323_fw_109

CROSS_COMPILE = arm-linux-uclibc-
TOOLCHAIN = $(PWD)/../toolchain_arm/toolchain_arm
PATH := $(TOOLCHAIN)/bin:$(PATH)

all: world

world: qemu kernel ramdisk flash hda run

# Mount sda2
# Offset = 1069286400 = 512 * 2088450 (2088450 == 2nd partition start sector
# from src/sfdisk.input)
mount:
	test -d sda2 || mkdir sda2
	sudo mount hda.img sda2 -o loop,offset=1069286400

# Unmount sda2
umount:
	sudo umount sda2

# Run QEMU
run:
	./qemu-system-arm \
		-m 128 \
		-M versatilepb \
		-nographic \
		-append "root=/dev/ram console=ttyAMA0 mtdparts=phys_mapped_flash:64k(MTD1),64k(MTD2)" \
		-pflash flash.img \
		-drive file=hda.img,index=0,if=scsi,serial=00001111 \
		-redir tcp:5022::22 \
		-redir tcp:5023::23 \
		-redir tcp:5080::80 \
		-initrd ramdisk_el.gz \
		-kernel zImage

# Create an empty 5G harddrive and lay down the funky DNS partitions
hda: hda.img
hda.img :
	qemu-img create -f raw hda.img 5G
	sfdisk -uS --force hda.img < src/sfdisk.input

# Create a dummy flash image (will be populated by the DNS firmware on first
# boot
flash: flash.img
flash.img:
	dd if=/dev/zero of=flash.img bs=1k count=128

# Download the DNS firmware and extract the ramdisk
ramdisk: ramdisk_el.gz
ramdisk_el.gz:
	( \
	cd src ; \
	wget ftp://ftp.dlink.com/Multimedia/dns323/Firmware/$(DNS_FW).zip ; \
	unzip $(DNS_FW).zip ; \
	cd $(DNS_FW) ; \
	../unpack $(DNS_FW) ; \
	cp ramdisk_el.gz ../../ ; \
	)

# Download, patch and compile the kernel (requires a cross-compiler)
kernel: zImage
zImage:
	( \
	cd src ; \
	wget ftp://ftp.kernel.org/pub/linux/kernel/v2.6/$(KERNEL).tar.bz2 ; \
	tar xjvf $(KERNEL).tar.bz2 ; \
	cd $(KERNEL) ; \
	patch -p1 < ../$(KERNEL)-dns323.patch ; \
	make ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) zImage ; \
	cp -f arch/arm/boot/zImage ../../ ; \
	)

# Download, patch, configure and compile QEMU
qemu: qemu-system-arm
qemu-system-arm:
	( \
	cd src ; \
	wget http://wiki.qemu.org/download/$(QEMU).tar.gz ; \
	tar xzvf $(QEMU).tar.gz ; \
	cd $(QEMU) ; \
	patch -p1 < ../$(QEMU)-dns323.patch ; \
	./configure --target-list=arm-softmmu ; \
	make ; \
	cp arm-softmmu/qemu-system-arm ../../ ; \
	)

# Cleanup
clean:
	-rm -rf src/$(KERNEL) src/$(KERNEL).tar.bz2
	-rm -rf src/$(QEMU) src/$(QEMU).tar.gz
	-rm -rf src/$(DNS_FW)*
	-rm -rf qemu-system-arm zImage ramdisk_el.gz flash.img hda.img
