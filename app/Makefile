# Build early-display-service for ARM64 (static). Output: ../build/rootfs/bin/
CROSS_COMPILE ?= aarch64-linux-gnu-
CC     := $(CROSS_COMPILE)gcc
OUT    := ../build/rootfs/bin
TARGET := $(OUT)/early-display-service

all: $(TARGET)
$(TARGET): early-display.c | $(OUT)
	$(CC) -O2 -Wall -Wextra -static -o $@ $<
$(OUT):
	mkdir -p $@
clean:
	rm -f $(TARGET)
.PHONY: all clean
