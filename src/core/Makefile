include ../../Config
include ../../etc/etc/os-release
TARGET = lib/sys/core

BINTARGET = ../../bin/root/$(TARGET)
SRCS = $(wildcard *.c)
OBJS = $(SRCS:.c=.o)
LIBS =
LDFLAGS = -nostdlib -nodefaultlibs -nostartfiles
ARCHOBJS = $(filter-out $(ARCH)/start.o,$(wildcard $(ARCH)/*.o))
CFLAGS = -DDEBUG=$(DEBUG) -DOPTIMIZE=$(OPTIMIZE) -DOSZ_NAME='$(NAME)' -DOSZ_VER='$(VERSION)' -DARCH='"$(ARCH)"' \
 -fpic -nostdinc -I../../etc/include -I. -I./$(ARCH) -include ./$(ARCH)/platform.h \
 -Wall -ffreestanding -fno-builtin -mno-red-zone -mno-mmx -mno-sse -mno-sse2 -mno-sse3
ifeq ($(DEBUG),1)
CFLAGS +=
else
LDFLAGS += -Xlinker -s
endif

all: $(OBJS) $(BINTARGET)

%.o: %.c
	$(O)$(CC) $(OPT) $(CFLAGS) -c $< -o $@

platform:
	@make -e --no-print-directory -C $(ARCH) all | grep -v 'Nothing to be done' || true

font.o:
	@cp ../../etc/system.8x16.psf ./font
	$(O)objcopy -O elf64-x86-64 -B i386 -I binary font font.o
	@rm font

logo.o:
	$(O)objcopy -O elf64-x86-64 -B i386 -I binary logo.tga logo.o

$(BINTARGET): platform font.o logo.o $(SRCS)
	@echo "  src		$(TARGET) ($(ARCH))"
	$(O)$(CC) $(LDFLAGS) $(ARCH)/start.o $(OBJS) $(ARCHOBJS) font.o logo.o -T $(ARCH)/supervisor.ld -Xlinker --build-id=none -Xlinker --nmagic -Xlinker -static -o $(BINTARGET) $(LIBS)
ifeq ($(DEBUG),1)
	@echo "0000000000200000 _init" >../../bin/core.sym
	@../../tools/elftool.o -s 0 $(BINTARGET) | sort >>../../bin/core.sym
endif
	@# avoid accidental execution of core
	@#echo -n "OS/Z" | dd conv=notrunc of=$(BINTARGET) bs=1 seek=0 1>/dev/null 2>/dev/null
	@echo -ne '\003' | dd conv=notrunc of=$(BINTARGET) bs=1 seek=16 1>/dev/null 2>/dev/null

clean:
	@rm *.o $(ARCH)/*.o $(BINTARGET) ../../bin/*.sym 2>/dev/null || true
