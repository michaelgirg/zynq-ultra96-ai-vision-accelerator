CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
PYTHON ?= python3

BUILD := build
CFLAGS := -march=rv32im -mabi=ilp32 -mcmodel=medany -O2 -g \
          -ffreestanding -fno-builtin -fno-common -Wall -Wextra -Werror \
          -ffunction-sections -fdata-sections -Iinclude
LDFLAGS := -nostdlib -nostartfiles -Wl,--build-id=none -Wl,--gc-sections -Wl,-Map,$(BUILD)/controller.map \
           -T linker.ld

.PHONY: all clean

all: $(BUILD)/controller_imem.mem $(BUILD)/controller_dmem.mem $(BUILD)/controller_images.h $(BUILD)/controller.dis

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/startup.o: startup.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/main.o: src/main.c include/soc_address_map.h include/vision_accel_regs.h include/axi_dma_regs.h include/job_mailbox.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/controller.elf: $(BUILD)/startup.o $(BUILD)/main.o linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(BUILD)/startup.o $(BUILD)/main.o -o $@

$(BUILD)/controller_imem.bin: $(BUILD)/controller.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@

$(BUILD)/controller_dmem.bin: $(BUILD)/controller.elf
	$(OBJCOPY) -O binary --only-section=.data $< $@

$(BUILD)/controller_imem.mem: $(BUILD)/controller_imem.bin
	$(PYTHON) ../../scripts/bin_to_riscv_mem.py $< $@

$(BUILD)/controller_dmem.mem: $(BUILD)/controller_dmem.bin
	$(PYTHON) ../../scripts/bin_to_riscv_mem.py --offset-bytes 0x8000 $< $@

$(BUILD)/controller_images.h: $(BUILD)/controller_imem.mem $(BUILD)/controller_dmem.mem
	$(PYTHON) ../../scripts/riscv_mem_to_header.py $^ $@

$(BUILD)/controller.dis: $(BUILD)/controller.elf
	$(OBJDUMP) -d -S $< > $@

clean:
	rm -rf $(BUILD)
