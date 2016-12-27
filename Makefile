include Config

all: clrdd todogen util boot system apps images

clrdd:
	@rm bin/disk.dd

todogen:
	@grep -ni 'TODO:' `find . 2>/dev/null` 2>/dev/null | grep -v Binary | grep -v grep >TODO.txt || true

boot: loader/bootboot.bin loader/bootboot.efi

loader/kernel.img:
	@echo "LOADER"
	@make -e --no-print-directory -C loader/rpi-$(ARCH) | grep -v 'Nothing to be done' | grep -v 'rm bootboot'

loader/bootboot.bin:
	@echo "LOADER"
	@make -e --no-print-directory -C loader/mb-$(ARCH) | grep -v 'Nothing to be done' | grep -v 'rm bootboot'

loader/bootboot.efi:
	@echo "LOADER"
	@make -e --no-print-directory -C loader/efi-$(ARCH) | grep -v 'Nothing to be done' | grep -v 'rm bootboot'

util: tools
	@date +'#define OSZ_BUILD "%Y-%m-%d %H:%M:%S UTC"' >etc/include/lastbuild.h
	@echo '#define OSZ_ARCH "$(ARCH)"' >>etc/include/lastbuild.h
	@echo "TOOLS"
	@make --no-print-directory -C tools all | grep -v 'Nothing to be done' || true

system: src
	@echo "CORE"
	@make -e --no-print-directory -C src/core all | grep -v 'Nothing to be done' || true
	@make -e --no-print-directory -C src/lib/libc all | grep -v 'Nothing to be done' || true

apps: src
	@echo "USERSPACE"
	@make -e --no-print-directory -C src all | grep -v 'Nothing to be done' || true
	@echo "DRIVERS"
	@make -e --no-print-directory -C src drivers | grep -v 'Nothing to be done' || true

images: tools
	@echo "IMAGES"
	@make -e --no-print-directory -C tools images | grep -v 'Nothing to be done' | grep -v 'lowercase' || true

vdi: images
	@make -e --no-print-directory -C tools vdi | grep -v 'Nothing to be done' || true

vdmk: images
	@make -e --no-print-directory -C tools vdmk | grep -v 'Nothing to be done' || true

clean:
	@make -e --no-print-directory -C loader/efi-x86_64/zlib_inflate clean
	@make -e --no-print-directory -C src clean
	@make -e --no-print-directory -C tools clean
	@make -e --no-print-directory -C tools imgclean

test: testq

testefi:
	@echo "TEST"
	@echo
	qemu-system-x86_64 -name OS/Z -bios bios-TianoCoreEFI.bin -m 64 -d guest_errors -hda fat:bin/ESP -option-rom loader/bootboot.rom -monitor stdio

testq:
	@echo "TEST"
	@echo
	qemu-system-x86_64 -name OS/Z -sdl -m 16 -d guest_errors -hda bin/disk.dd -option-rom loader/bootboot.bin -monitor stdio

testb:
	@echo "TEST"
	@echo
ifneq ($(wildcard /usr/local/bin/bochs),)
	/usr/local/bin/bochs -f etc/bochs.rc -q
else
	bochs -f etc/bochs.rc -q
endif
