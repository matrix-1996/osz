include ../../../Config

SRCS = $(filter-out dbg.c disasm.c,$(wildcard *.c))
#ifeq $($(DEBUG),1)
SRCS += dbg.c disasm.c
#endif
SRCS+= $(wildcard *.S)
TMP = $(SRCS:.c=.o)
OBJS = $(TMP:.S=.o)
CFLAGS = -DDEBUG=$(DEBUG) -DOPTIMIZE=$(OPTIMIZE) -DOSZ_NAME='$(NAME)' -DOSZ_VER='$(VERSION)' -DARCH='"$(ARCH)"' \
 -Wall -fpic -ffreestanding -nostdinc -I ../../../etc/include -include platform.h -include ../env.h

all: $(OBJS) ok

isrs.S: isr.h isrs.sh isr.c
	@./isrs.sh $(ARCH) 2>/dev/null || true

ok:
	@true

%.o: %.S
	$(O)$(CC) -D_AS=1 $(OPT) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(O)$(CC) $(OPT) $(CFLAGS) -c $< -o $@

clean:
	@rm *.o 2>/dev/null || true
