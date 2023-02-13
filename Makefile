DEFAULT_TARGET=JDC-1.mak
ifeq ($(wildcard target.mak),)
  $(warning Can not find target file: target.mak)
  ifeq ($(wildcard targets/$(DEFAULT_TARGET)),)
    $(warning Can not find default target file: targets/$(DEFAULT_TARGET))
    TARGETS=$(wildcard targets/*.mak)
    ifeq ($(TARGETS),)
      $(error Check directory "targets")
    endif
    $(foreach name,$(TARGETS),$(warning ln -sf $(name) target.mak))
    $(error Run one of above command first)
  else
    $(warning "Target not exist, Use default target: $(DEFAULT_TARGET)")
    $(shell ln -sf targets/$(DEFAULT_TARGET) target.mak)
  endif
endif

include target.mak
TARGET_DIR=$(shell readlink target.mak | sed 's/.*\///;s/.mak//')
FIRMWARE_DIR=$(TARGET_DIR)/firmware
TEMP_DIR=$(TARGET_DIR)/temp

#Check variables in target.mak
ifeq ($(TOOL_PATH),)
  $(error variable "TOOL_PATH" not defined)
endif
ifeq ($(wildcard $(TOOL_PATH)),)
  $(error TOOL_PATH: ($(TOOL_PATH)) not exist)
else
  TEMP=$(abspath $(TOOL_PATH))
  TOOL_PATH:=$(TEMP)
endif
ifeq ($(URL),)
  $(error variable "URL" not defined)
endif

TEMP=$(PATH)
PATH:=$(TEMP):$(TOOL_PATH)
export PATH
MKIMAGE:=$(TOOL_PATH)/mkimage
MKSQUASHFS:=$(TOOL_PATH)/mksquashfs
UNSQUASHFS:=$(TOOL_PATH)/unsquashfs
CHECK_LIST=$(MKIMAGE) $(MKSQUASHFS) $(UNSQUASHFS)
$(foreach name,$(CHECK_LIST),$(eval $(if $(wildcard $(name)),,$(error Can not find tool: $(name)))))
BINWALK=$(shell which binwalk)
ifeq ($(BINWALK),)
  $(error Can not find \"binwalk\", install it first)
endif

TEMP=$(subst /, ,$(URL))
TARGET:=$(FIRMWARE_DIR)/$(word $(words $(TEMP)),$(TEMP))

TEMP:=$(shell mkdir -p $(FIRMWARE_DIR) $(TEMP_DIR))

.PHONY: info unpack download repack dir

info:$(TARGET).info
	@echo "Target: $(TARGET)"
	@cat $<

unpack: $(TARGET).info
	offset=`cat $< | sed '/Squashfs filesystem/!d;s/^\([0-9]*\).*/\1/'`;\
	dd if=$(TARGET) of=$(TEMP_DIR)/uImage bs=$$offset count=1;\
	dd if=$(TEMP_DIR)/uImage of=$(TEMP_DIR)/zImage bs=64 skip=1;\
	dd if=$(TARGET) of=$(TEMP_DIR)/rootfs bs=$$offset skip=1
	cd $(TEMP_DIR);rm -rf squashfs-root;$(UNSQUASHFS) rootfs # -d squashfs-root

repack: $(TARGET).info
	@cd $(TEMP_DIR);mksquashfs squashfs-root/ rootfs.new  -all-root -no-exports -noappend -nopad -noI -no-xattrs -comp xz
	@cp $(TEMP_DIR)/zImage $(TEMP_DIR)/zImage.new
	@cat $(TEMP_DIR)/rootfs.new >>$(TEMP_DIR)/zImage.new
	@entry=`cat $< | sed '/^Entry Point/!d;s/.*0x0*/0x/'`;\
	load=`cat $< | sed '/^Load Address/!d;s/.*0x0*/0x/'`;\
	ksize=`cat $< | sed '/^Kernel Size/!d;s/.*0x0*/0x/'`;\
	comp=`cat $< | sed '/^Image Type/!d;s/.*(//;s/ .*//'`;\
	arch=`cat $< | sed '/^Image Type/!d;s/.*: *//;s/ .*//;s/[A-Z]/\l&/g'`;\
	name=`cat $< | sed '/^Product ID/!d;s/.*: *//'`;\
	kver=`cat $< | sed '/^Kernel Ver/!d;s/.*: *//'`;\
	fver=`cat $< | sed '/^FS Ver/!d;s/.*: *//'`;\
	ksize=`printf "%u\n" $$ksize`;\
	[ -n "$$kver$$fver" ] && VER="-V $$kver $$fver";\
	[ -n "$$ksize" ] && KSIZE="-k `printf "%u\n" $$ksize`";\
	$(MKIMAGE) -O linux -T kernel -A $$arch -C $$comp -a $$load -e $$entry -n "$$name" $$VER $$KSIZE -d $(TEMP_DIR)/zImage.new $(TARGET).new 
	@echo "Final target is: $(TARGET).new"


download $(TARGET):
	wget --no-check-certificate $(URL) -O $(TARGET)

$(TARGET).info:$(TARGET)
	@$(MKIMAGE) -l $< >$@
	@$(BINWALK) $< >>$@

clean:
	@rm -rf $(TEMP_DIR)
	@rm -rf $(FIRMWARE_DIR)
