#########################################################################################################
##
## Name:            Makefile
## Created:         January 2019
## Author(s):       Philip Smart
## Description:     ZPU IO Control Program makefile
##                  This makefile builds the IOCP binary which is used for booting the ZPU. The
##                  purpose of the IOCP is to boot/upload an application and provide basic test
##                  facilities.
##
## Credits:         
## Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
##
## History:         January 2019   - Initial script written for the STORM processor then changed to the ZPU.
##
## Notes:           Optional component enables:
##                  USELOADB              - The Byte write command is implemented in hw#sw so use it.
##                  USE_BOOT_ROM          - The target is ROM so dont use initialised data.
##                  MINIMUM_FUNTIONALITY  - Minimise functionality to limit code size.
##
#########################################################################################################
## This source file is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This source file is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
#########################################################################################################
BASE        	= zpu-elf
CC              = $(BASE)-gcc
LD              = $(BASE)-gcc
AS              = $(BASE)-as
CP              = $(BASE)-objcopy
DUMP            = $(BASE)-objdump

# Version to build, full, medium, minimum or tiny. 0 = Full, 1 = Medium, 2 = Minimum, 3 = Tiny.
ifeq ($(FUNCTIONALITY), )
FUNCTIONALITY   = 3
endif

# Addresses where the IOCP base program loads and where the app it autoloads will load and execute.
ifeq ($(IOCP_BASEADDR), )
IOCP_BASEADDR   = 0x000000
endif
ifeq ($(IOCP_APPADDR), )
IOCP_APPADDR    = 0x001000
endif

BASEDIR         = ../..
#BASEDIR        = ../../..
SWDIR           = $(BASEDIR)/software
#SWDIR          = $(BASEDIR)/software/zpu
ROMGEN          = $(SWDIR)/utils/zpugen

# we use mincrt0.s from here
STARTUP_DIR     = $(SWDIR)/startup

# we fetch ROM prologue / epilogue from here
RTL_DIR         = $(BASEDIR)/devices/sysbus/BRAM

# we use printf from here
COMMON_DIR      = $(SWDIR)/common
PFS_DIR         = $(SWDIR)/common/PetitFS
INCLUDE_DIR     = $(SWDIR)/include

# Linker mapping file spec file.
LINKMAP         = $(STARTUP_DIR)/iocp_bram_${IOCP_BASEADDR}.ld

# Working directory to build object files.
BUILD_DIR       = iocp_obj

#MINSTARTUP_SRC = $(STARTUP_DIR)/mincrt0.s $(STARTUP_DIR)/pre_rom_main.s
#MINSTARTUP_SRC = $(STARTUP_DIR)/crt0.s $(STARTUP_DIR)/pre_rom_main.s
#MINSTARTUP_SRC = $(STARTUP_DIR)/atari_crt0.s 
MINSTARTUP_SRC  = $(STARTUP_DIR)/romcrt0.s $(STARTUP_DIR)/pre_rom_main.s

#MINSTARTUP_SRC = $(STARTUP_DIR)/crt0_phi.S $(STARTUP_DIR)/pre_rom_main.s
MINSTARTUP_OBJ  = $(patsubst $(STARTUP_DIR)/%.s,$(BUILD_DIR)/%.o,$(MINSTARTUP_SRC))

COMMON_SRC      = $(COMMON_DIR)/uart.c
ifneq ($(FUNCTIONALITY), 3)
COMMON_SRC     += $(COMMON_DIR)/zpu_soc.c $(COMMON_DIR)/simple_utils.c $(COMMON_DIR)/interrupts.c 
endif
PFS_SRC         = $(PFS_DIR)/sdmmc.c $(PFS_DIR)/pff.c
#
COMMON_OBJ      = $(patsubst $(COMMON_DIR)/%.c,$(BUILD_DIR)/%.o,$(COMMON_SRC))
PFS_OBJ         = $(patsubst $(PFS_DIR)/%.c,$(BUILD_DIR)/%.o,$(PFS_SRC))
#
MAIN_PRJ        = iocp
MAIN_SRC        = iocp.c
MAIN_OBJ        = $(COMMON_OBJ) $(PFS_OBJ) $(patsubst %.c,$(BUILD_DIR)/%.o,$(MAIN_SRC))

# Commandline options for each tool.
#
# To disable use of a given instruction, prefix it with no-
ZPUOPTS         = -mmult \
	 	          -mdiv \
	          	  -mmod \
	          	  -mneg \
	          	  -mloadsp \
	          	  -mstoresp \
	          	  -mpushspadd \
	          	  -mneqbranch \
	          	  -maddsp \
	          	  -mashiftrt \
	          	  -mashiftl \
	          	  -mlshiftrt \
	          	  -mcall \
	          	  -mcallpcrel \
	          	  -mshortop \
	          	  -mbyteop \
	          	  -meq \
	          	  -mcompare \
	          	  -mpoppcrel \
	          	  -mmemreg
#CFLAGS          = -I. -I$(COMMON_DIR) -I$(PFS_DIR) -I$(INCLUDE_DIR) -c -Os $(ZPUOPTS) -DZPU -DIOCP -DPFS -DIOCP_BASEADDR=$(IOCP_BASEADDR) -DIOCP_APPADDR=$(IOCP_APPADDR) -DFUNCTIONALITY=$(FUNCTIONALITY)
CFLAGS          = -I. -I$(COMMON_DIR) -I$(PFS_DIR) -I$(INCLUDE_DIR) -c -Os -ffunction-sections -fdata-sections $(ZPUOPTS) -DZPU -DIOCP -DPFS -DIOCP_BASEADDR=$(IOCP_BASEADDR) -DIOCP_APPADDR=$(IOCP_APPADDR) -DFUNCTIONALITY=$(FUNCTIONALITY)
#
# Limit functionality to save space using this flag.
CFLAGS         += -DMINIMUM_FUNCTIONALITY
# Enable debug output.
OFLAGS         += -DDEBUG
# Assume loadb as implemented in hardware or software (time penalty).
OFLAGS         += -DUSELOADB
# Dont allow an initialised DATA segment so binary can be located in ROM.
	#OFLAGS    += -DUSE_BOOT_ROM
# Remove functionality to create a minimal system for limited space.
	#OFLAGS    += -DMINIMUM_FUNCTIONALITY
#
#LFLAGS         = -nostartfiles -nostdlib -Wl,--relax -Os -Wl,-Map,$(MAIN_PRJ).map
LFLAGS          = -nostartfiles -Wl,--gc-sections -Wl,--relax -Wl,-Map,$(MAIN_PRJ).map -Os
#LFLAGS         = -nostartfiles -Wl,--relax -Os

# Assembler flags.
ASFLAGS         = -I. -I$(COMMON_DIR) -I$(INCLUDE_DIR) -I$(STARTUP_DIR) --defsym IOCP_BASEADDR=$(IOCP_BASEADDR) --defsym IOCP_APPADDR=$(IOCP_APPADDR)

# Our target.
all: $(BUILD_DIR) $(MAIN_PRJ).bin $(MAIN_PRJ).srec $(MAIN_PRJ).rpt $(MAIN_PRJ).lss $(MAIN_PRJ).dmp $(ROMGEN) $(MAIN_PRJ)_ROM.vhd

clean:
	rm -f $(BUILD_DIR)/*.o *.hex *.lss *.elf *.map *.lst *.srec $(MAIN_PRJ).rom *~ */*.o *.bin *.srec *.dmp *.vhd *.rpt


# Convert ELF binary to bin file.
%.bin: %.elf
	@$(CP) -O binary $< $@

# Convert ELF to srec format for serial upload.
%.srec: %.elf
	@$(CP) -O srec $< $@

%.rpt: %.elf
	@echo ""
	@echo >$@ -n  "Start of code:\t"
	@$(DUMP) -x $< | grep >>$@ _bramstart
	@echo >>$@ -n "  BOOT start:\t"
	@$(DUMP) -x $< | grep  >>$@ __boot_start__
	@echo >>$@ -n "       end:  \t"
	@$(DUMP) -x $< | grep >>$@ __boot_end__
	@echo >>$@ -n "  TEXT start:\t"
	@$(DUMP) -x $< | grep  >>$@ __text_start__
	@echo >>$@ -n "       end:  \t"
	@$(DUMP) -x $< | grep >>$@ __text_end__
	@echo >>$@ -n "  RODATA start:\t"
	@$(DUMP) -x $< | grep  >>$@ __rodata_start__
	@echo >>$@ -n "         end:  \t"
	@$(DUMP) -x $< | grep >>$@ __rodata_end__
	@echo >>$@ -n "End of code:\t"
	@$(DUMP) -x $< | grep >>$@ _bramend
	@echo >>$@ -n  "Start of data:\t"
	@$(DUMP) -x $< | grep >>$@ _datastart
	@echo >>$@ -n "  DATA start: \t"
	@$(DUMP) -x $< | grep  >>$@ __data_start__
	@echo >>$@ -n "       end:   \t"
	@$(DUMP) -x $< | grep >>$@ __data_end__
	@echo >>$@ -n "  BSS start:  \t"
	@$(DUMP) -x $< | grep  >>$@ __bss_start__
	@echo >>$@ -n "      end:    \t"
	@$(DUMP) -x $< | grep >>$@ __bss_end__
	@echo >>$@ -n "End of data:\t"
	@$(DUMP) -x $< | grep >>$@ _dataend
	@cat $@

%.dmp: %.elf
	@$(DUMP) -x $< >>$@

# Create extended listing file from ELF output file.
# testing: option -C
%.lss: %.elf
	@echo
	@$(DUMP) -h -S -C $< > $@

$(ROMGEN): $(SWDIR)/utils/zpugen.c
	gcc -o $(SWDIR)/utils/zpugen $(SWDIR)/utils/zpugen.c
	chmod +x $(SWDIR)/utils/zpugen

zpugen: $(SWDIR)/utils/zpugen.c
	gcc -o $(SWDIR)/utils/zpugen $(SWDIR)/utils/zpugen.c

%_ROM.vhd: %.bin $(ROMGEN)
	@sed 's/dualportram/BootROM/' >IOCP_BootROM.vhd <$(RTL_DIR)/rom_prologue.vhd
	@$(ROMGEN) 4 $*.bin >>IOCP_BootROM.vhd
	@cat >>IOCP_BootROM.vhd $(RTL_DIR)/rom_epilogue.vhd
	@cp IOCP_BootROM.vhd $(RTL_DIR)/

	@sed 's/byteaddr_dp_32bit_bram/DualPortBootBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_dp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BA $*.bin /tmp/zpu_work.tmp >IOCP_DualPortBootBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp IOCP_DualPortBootBRAM.vhd $(RTL_DIR)/

	@sed 's/byteaddr_sp_32bit_bram/SinglePortBootBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_sp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BA $*.bin /tmp/zpu_work.tmp >IOCP_SinglePortBootBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp IOCP_SinglePortBootBRAM.vhd $(RTL_DIR)/

	@sed 's/byteaddr_sp_32bit_bram/SinglePortBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_sp_32bit_bram_tmpl.vhd
	@grep -v BYTEARRAY_ < /tmp/zpu_work.tmp > IOCP_SinglePortBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp IOCP_SinglePortBRAM.vhd $(RTL_DIR)/

	@rm IOCP_BootROM.vhd IOCP_DualPortBootBRAM.vhd IOCP_SinglePortBootBRAM.vhd IOCP_SinglePortBRAM.vhd
	@echo "IOCP_BootROM.vhd, IOCP_DualPortBootBRAM.vhd, IOCP_SinglePortBootBRAM and IOCP_SinglePortBRAM updated."

# Link - this produces an ELF binary.

$(MAIN_PRJ).elf: $(MINSTARTUP_OBJ) $(MAIN_OBJ)
	$(LD) $(LFLAGS) -T $(LINKMAP) -o $@ $+ $(LIBS)

$(BUILD_DIR)/%.o: %.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: %.cpp Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: $(COMMON_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: $(PFS_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS)  -o $@ -c $<

$(BUILD_DIR)/%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/%.o: $(STARTUP_DIR)/%.s
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir $(BUILD_DIR)

