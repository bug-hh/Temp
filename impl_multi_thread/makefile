BUILD_DIR = ./build
ENTRY_POINT = 0xc0001500
AS = nasm
CC = gcc
LD = ld
USER_NAME = $(shell whoami)
ASLIB = -I boot/src/include/
LIB = -I lib/ -I lib/kernel/ -I lib/user/ -I kernel/src -I device/src -I thread/
ASFLAGS = -f elf
CFLAGS = -m32 -Wall $(LIB) -c -fno-builtin -W -Wstrict-prototypes \
         -Wmissing-prototypes 
LDFLAGS = -m elf_i386 -Ttext $(ENTRY_POINT) -e main -Map $(BUILD_DIR)/kernel.map
OBJS = $(BUILD_DIR)/main.o $(BUILD_DIR)/init.o $(BUILD_DIR)/interrupt.o \
      $(BUILD_DIR)/timer.o $(BUILD_DIR)/kernel.o $(BUILD_DIR)/print.o \
      $(BUILD_DIR)/debug.o $(BUILD_DIR)/memory.o $(BUILD_DIR)/bitmap.o \
	  $(BUILD_DIR)/string.o $(BUILD_DIR)/thread.o $(BUILD_DIR)/list.o \
	  $(BUILD_DIR)/switch.o 

##############     c代码编译     ###############
$(BUILD_DIR)/main.o: kernel/src/main.c lib/kernel/print.h \
        lib/stdint.h kernel/src/init.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/init.o: kernel/src/init.c kernel/src/init.h lib/kernel/print.h \
        lib/stdint.h kernel/src/interrupt.h device/src/timer.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/interrupt.o: kernel/src/interrupt.c kernel/src/interrupt.h \
        lib/stdint.h kernel/src/global.h lib/kernel/io.h lib/kernel/print.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/timer.o: device/src/timer.c device/src/timer.h lib/stdint.h\
         lib/kernel/io.h lib/kernel/print.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/debug.o: kernel/src/debug.c kernel/src/debug.h \
        lib/kernel/print.h lib/stdint.h kernel/src/interrupt.h
	$(CC) $(CFLAGS) $< -o $@
	
$(BUILD_DIR)/string.o: lib/string.c lib/string.h lib/stdint.h kernel/src/global.h \
	lib/stdint.h kernel/src/debug.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/bitmap.o: lib/kernel/bitmap.c lib/kernel/bitmap.h \
    	kernel/src/global.h lib/stdint.h lib/string.h lib/stdint.h \
     	lib/kernel/print.h kernel/src/interrupt.h kernel/src/debug.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/memory.o: kernel/src/memory.c kernel/src/memory.h lib/stdint.h lib/kernel/bitmap.h \
   	kernel/src/global.h kernel/src/global.h kernel/src/debug.h lib/kernel/print.h \
	lib/kernel/io.h kernel/src/interrupt.h lib/string.h lib/stdint.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/thread.o: thread/thread.c thread/thread.h lib/stdint.h kernel/src/memory.h kernel/src/global.h lib/string.h 
	$(CC) $(CFLAGS) $< -o $@
	
$(BUILD_DIR)/list.o: lib/kernel/list.c lib/kernel/list.h kernel/src/global.h lib/stdint.h \
        kernel/src/interrupt.h
	$(CC) $(CFLAGS) $< -o $@

##############    汇编代码编译    ###############
$(BUILD_DIR)/kernel.o: kernel/src/kernel.S
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD_DIR)/print.o: lib/kernel/print.S
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD_DIR)/switch.o: thread/switch.S 
	$(AS) $(ASFLAGS) $< -o $@
$(BUILD_DIR)/loader.bin: boot/src/loader.S boot/src/include/boot.inc 
	$(AS) $(ASLIB) -o $(BUILD_DIR)/loader.bin boot/src/loader.S 
$(BUILD_DIR)/mbr.bin: boot/src/mbr.S boot/src/include/boot.inc 
	$(AS) $(ASLIB) -o $(BUILD_DIR)/mbr.bin boot/src/mbr.S

##############    链接所有目标文件    #############
$(BUILD_DIR)/kernel.bin: $(OBJS)
	$(LD) $(LDFLAGS) $^ -o $@

.PHONY : mk_dir hd clean all

mk_dir:
	if [[ ! -d $(BUILD_DIR) ]];then mkdir $(BUILD_DIR);fi

hd_mbr:
	dd if=$(BUILD_DIR)/mbr.bin of=/home/$(USER_NAME)/OSProject/hd60M.img bs=512 count=1 seek=0 conv=notrunc

hd_loader:
	dd if=$(BUILD_DIR)/loader.bin of=/home/$(USER_NAME)/OSProject/hd60M.img bs=512 count=3 seek=2 conv=notrunc

hd_kernel:
	dd if=$(BUILD_DIR)/kernel.bin \
           of=/home/$(USER_NAME)/OSProject/hd60M.img \
           bs=512 count=200 seek=9 conv=notrunc

clean:
	cd $(BUILD_DIR) && rm -f ./*

build: $(BUILD_DIR)/mbr.bin $(BUILD_DIR)/loader.bin $(BUILD_DIR)/kernel.bin

start:
	bochs -f /home/$(USER_NAME)/OSProject/bochsrc.disk

all: mk_dir build hd_mbr hd_loader hd_kernel start
