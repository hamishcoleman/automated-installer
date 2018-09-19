#
# Build an installer image to boot a bare-metal server and install a ZFS root
# disk
#

all: bootable-images

SUBDIRS := debian kernel

CLEAN_FILES := nothing

CONFIGDIRS := .
CONFIGDIRS += $(abspath zfs-config)
export CONFIGDIRS

# The minimal install system is built as this arch, not the installed server
CONFIG_DEBIAN_ARCH := i386
export CONFIG_DEBIAN_ARCH

CONFIG_DEBIAN_VER := stretch

SHELL_URL := https://github.com/tianocore/edk2/raw/UDK2018/ShellBinPkg/UefiShell/X64/Shell.efi

ISODIR := iso
DISK_IMAGE := $(ISODIR)/boot.img
ISO_IMAGE := boot.iso

.PHONY: bootable-images
bootable-images: $(DISK_IMAGE) $(ISO_IMAGE)

build-depends: debian/Makefile
	$(foreach dir,$(SUBDIRS),$(MAKE) -C $(dir) $@ &&) true
	sudo apt -y install ovmf xorriso expect mtools

# Calculate the basename of the debian build file
DEBIAN_BASENAME = debian.$(CONFIG_DEBIAN_VER).$(CONFIG_DEBIAN_ARCH)
DEBIAN = debian/build/$(DEBIAN_BASENAME)

# Rules to go and make the debian installed root
# Note: this has no dependancy checking, and will simply use what ever
# file is there
.PHONY: debian
debian: debian/Makefile
	$(MAKE) -C debian build/$(DEBIAN_BASENAME).cpio

$(DEBIAN).cpio: debian

# Ensure that the submodule is actually present
debian/Makefile:
	git submodule update --init --remote

kernel/ubuntu.amd64.kernel kernel/ubuntu.amd64.modules.cpio:
	$(MAKE) -C kernel all

combined.initrd: $(DEBIAN).cpio kernel/ubuntu.amd64.modules.cpio
	cat $^ >$@

Shell.efi:
	wget -O $@ $(SHELL_URL)
CLEAN_FILES += Shell.efi

# Create a file with the size of the needed disk image in it
size.txt: combined.initrd kernel/ubuntu.amd64.kernel Shell.efi
	echo $$(($$(stat -c %s combined.initrd)/1048576 +$$(stat -c %s kernel/ubuntu.amd64.kernel)/1048576 +$$(stat -c %s Shell.efi)/1048576 +3)) >$@

$(DISK_IMAGE): size.txt startup.nsh combined.initrd kernel/ubuntu.amd64.kernel Shell.efi
	mkdir -p $(dir $@)
	truncate --size=$$(cat size.txt)M $@.tmp
	mformat -i $@.tmp -v EFS -N 2 -t $$(cat size.txt) -h 64 -s 32 ::
	mmd -i $@.tmp ::efi
	mmd -i $@.tmp ::efi/boot
	mcopy -i $@.tmp Shell.efi ::efi/boot/bootx64.efi
	mcopy -i $@.tmp kernel/ubuntu.amd64.kernel ::linux.efi
	mcopy -i $@.tmp combined.initrd ::initrd
	mcopy -i $@.tmp startup.nsh ::
	mcopy -i $@.tmp install.nsh ::
	mv $@.tmp $@

$(ISO_IMAGE): $(DISK_IMAGE)
	xorrisofs \
	    -o $@ \
	    --efi-boot $(notdir $(DISK_IMAGE)) \
	    $(ISODIR)

persistent.storage:
	truncate $@ --size=10G
REALLYCLEAN_FILES += persistent.storage

SHELL_SCRIPTS := \
	zfs-config/packages.d/_ALWAYS.customise.add/usr/local/sbin/statuspage \
	zfs-config/packages.d/_ALWAYS.customise.add/zfs.install \
	zfs-config/packages.d/_ALWAYS.customise.add/zfs.d/*.sh \
	zfs-config/packages.d/_ALWAYS.customise.add/zfs.d/inchroot/*.sh \

# Run a shell linter
shellcheck:
	shellcheck --shell bash $(SHELL_SCRIPTS)

QEMU_RAM := 1500
QEMU_CMD_NET := -netdev type=user,id=e0 -device virtio-net-pci,netdev=e0
QEMU_CMD_EFI := \
    -drive if=pflash,format=raw,unit=0,file=/usr/share/ovmf/OVMF.fd,readonly=on
QEMU_CMD_CDROM := -cdrom $(ISO_IMAGE)
QEMU_CMD_SERIALONLY := -display none -serial null -serial stdio
QEMU_CMD_SERIAL2 := -serial vc -serial stdio
QEMU_CMD_DRIVE0 := -drive if=virtio,cache=unsafe,format=raw,file=persistent.storage

QEMU_CMD := qemu-system-x86_64 \
    -machine pc,accel=kvm:tcg -cpu qemu64,-svm \
    -m $(QEMU_RAM)

# Just build the initramfs and boot it directly
test_quick: combined.initrd kernel/ubuntu.amd64.kernel
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    -append console=ttyS0 \
	    -kernel kernel/ubuntu.amd64.kernel \
	    -initrd combined.initrd \
	    -nographic

# Test the EFI boot - with the 'normal' image wrapped in a ISO
test_efi: $(ISO_IMAGE)
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    $(QEMU_CMD_EFI) \
	    $(QEMU_CMD_CDROM) \
	    $(QEMU_CMD_SERIALONLY)

# Test EFI booting, with an actual graphics console visible
test_efigui: $(ISO_IMAGE)
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    $(QEMU_CMD_EFI) \
	    $(QEMU_CMD_CDROM) \
	    $(QEMU_CMD_SERIAL2)

# Test the EFI boot - with the 'simplified' image - not wrapped
test_efihd_persist: $(DISK_IMAGE) persistent.storage
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    $(QEMU_CMD_EFI) \
	    $(QEMU_CMD_SERIALONLY) \
	    $(QEMU_CMD_DRIVE0) \
	    -drive if=virtio,format=raw,id=boot,file=$(DISK_IMAGE)

# Test just booting the persistend hard disk
test_installed: persistent.storage
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    $(QEMU_CMD_EFI) \
	    $(QEMU_CMD_SERIALONLY) \
	    $(QEMU_CMD_DRIVE0)

test_efi_persist: $(ISO_IMAGE) persistent.storage
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    $(QEMU_CMD_EFI) \
	    $(QEMU_CMD_CDROM) \
	    $(QEMU_CMD_SERIALONLY) \
	    $(QEMU_CMD_DRIVE0)

test_efigui_persist: $(ISO_IMAGE) persistent.storage
	$(QEMU_CMD) \
	    $(QEMU_CMD_NET) \
	    $(QEMU_CMD_EFI) \
	    $(QEMU_CMD_CDROM) \
	    $(QEMU_CMD_SERIAL2) \
	    $(QEMU_CMD_DRIVE0)

# TODO - define the ROOT password only in one place, instead of here and in the
# debian/ submodule
INSTALLER_ROOT_PASS:=root

# Common definitions used for all test targets
TEST_HARNESS := ./debian/scripts/test_harness
TEST_TARGET := test_efihd_persist
TEST_INSTALLED_TARGET := test_installed
TEST_ARGS := config_pass=$(INSTALLER_ROOT_PASS)

TESTS_INSTALLED_BOOT := tests/15boot.expect tests/20login_installed.expect

TESTS_STAGE1 := tests/01boot.expect tests/05login_installer.expect \
    tests/07waitjobs.expect \
    tests/09set.stage1.optional \
    tests/10install1.expect \
    tests/10install1.stop.optional
TESTS_STAGE2 := tests/01boot.expect tests/05login_installer.expect \
    tests/07waitjobs.expect \
    tests/10install2.resume.optional \
    tests/10install2.expect \
    tests/15boot.expect \
    tests/20login_installed.expect

# Run a test script for perform a full system install
# Assume that test.full always needs the full set of travis test helpers
# (idlebust and timestamps
.PHONY: test.full
test.full: debian/Makefile
	rm -f test.full
	rm -f persistent.storage
	$(TEST_HARNESS) "make $(TEST_TARGET)" $(TEST_ARGS) \
	    config_idlebust=1 config_timestamps=1 config_nossh=1 \
	    $(TEST_EXTRA) \
	    tests/*.expect
	touch test.full

test.installed.boot:
	$(TEST_HARNESS) "make $(TEST_INSTALLED_TARGET)" $(TEST_ARGS) \
	    $(TEST_EXTRA) \
	    $(TESTS_INSTALLED_BOOT)

# Split the build into multiple stages
.PHONY: test.stage1 test.stage2
test.stage1: debian/Makefile ; $(TEST_CMD) $(TESTS_STAGE1) config_idlebust=1
test.stage2: debian/Makefile ; $(TEST_CMD) $(TESTS_STAGE2) config_idlebust=1

.PHONY: test
test: shellcheck build-depends debian bootable-images test.full

clean:
	$(foreach dir,$(SUBDIRS),$(MAKE) -C $(dir) $@ ;) true
	rm -f $(CLEAN_FILES)

reallyclean:
	$(foreach dir,$(SUBDIRS),$(MAKE) -C $(dir) $@ &&) true
	rm -f $(REALLYCLEAN_FILES)
