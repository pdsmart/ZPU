#########################################################################################################
##
## Name:            Makefile
## Created:         January 2019
## Author(s):       Philip Smart
## Description:     ZPU Test Application (zputa)
##                  This makefile builds the ZPUTA application the purpose of which is to provide test 
##                  and monitoring tools for ZPU and devices within the SoC. 
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
##                  COREMARK_TEST         - Add the CoreMark test suite.
##                  DHYRSTONE_TEST        - Add the Dhrystone test suite.
##                  USE_SDCARD            - Add the SDCard logic.
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
BASE	        = zpu-elf
CC              = $(BASE)-gcc
LD              = $(BASE)-gcc
AS              = $(BASE)-as
CP              = $(BASE)-objcopy
DUMP            = $(BASE)-objdump

# Addresses where the ZPUTA base program loads and where apps load and execute.
# With IOCP. These are defaults as they should be overriden by caller.
ifeq ($(ZPUTA_BASEADDR),)
ZPUTA_BASEADDR = 0x01000
endif
ifeq ($(ZPUTA_APPADDR),)
ZPUTA_APPADDR  = 0x0C000
endif

BASEDIR         = ../..
#BASEDIR        = ../../..
SWDIR           = $(BASEDIR)/software
#SWDIR          = $(BASEDIR)/software/zpu
ROMGEN          = $(SWDIR)/utils/zpugen
IOCPDIR         = $(SWDIR)/iocp

# we use mincrt0.s from here
STARTUP_DIR     = $(SWDIR)/startup

# we fetch RAM prologue / epilogue from here
RTL_DIR         = $(BASEDIR)/devices/sysbus/BRAM

# we use printf from here
COMMON_DIR      = $(SWDIR)/common
DHRY_DIR        = $(SWDIR)/common/Dhrystone
CORE_DIR        = $(SWDIR)/common/CoreMark
FATFS_DIR       = $(SWDIR)/common/FatFS
PFS_DIR         = $(SWDIR)/common/PetitFS
INCLUDE_DIR     = $(SWDIR)/include

# Linker mapping file spec file.
LINKMAPBOOTSTANDALONE = $(STARTUP_DIR)/zputa_standalone_boot_in_bram.ld
LINKMAPBOOTIOCP       = $(STARTUP_DIR)/zputa_with_iocp_in_bram.ld
LINKMAPBOOTTINYIOCP   = $(STARTUP_DIR)/zputa_with_tiny_iocp_in_bram.ld
LINKMAPRAM            = $(STARTUP_DIR)/zputa_as_app_in_ram.ld

# Working directory to build object files.
BUILD_DIR       = zpu_obj

# Startup files, RAM has no microcode, ROM has microcode.
RAMSTARTUP_SRC  = $(STARTUP_DIR)/ramcrt0.s $(STARTUP_DIR)/pre_ram_main.s
RAMSTARTUP_OBJ  = $(patsubst $(STARTUP_DIR)/%.s,$(BUILD_DIR)/%.o,$(RAMSTARTUP_SRC))
ROMSTARTUP_SRC  = $(STARTUP_DIR)/zputaromcrt0.s #$(STARTUP_DIR)/pre_rom_main.s
ROMSTARTUP_OBJ  = $(patsubst $(STARTUP_DIR)/%.s,$(BUILD_DIR)/%.o,$(ROMSTARTUP_SRC))

COMMON_SRC      = $(COMMON_DIR)/utils.c $(COMMON_DIR)/uart.c $(COMMON_DIR)/zpu_soc.c $(COMMON_DIR)/interrupts.c $(COMMON_DIR)/ps2.c $(COMMON_DIR)/swap.c $(COMMON_DIR)/spi.c $(COMMON_DIR)/syscalls.c $(COMMON_DIR)/malloc.c $(COMMON_DIR)/xprintf.c
DHRY_SRC        = $(DHRY_DIR)/dhry_1.c $(DHRY_DIR)/dhry_2.c
CORE_SRC        = $(CORE_DIR)/core_list_join.c $(CORE_DIR)/core_main_embedded.c $(CORE_DIR)/core_matrix.c $(CORE_DIR)/core_state.c $(CORE_DIR)/core_util.c $(CORE_DIR)/ee_printf.c $(CORE_DIR)/core_portme.c
FATFS_SRC       = $(FATFS_DIR)/sdmmc.c $(FATFS_DIR)/ff.c
PFS_SRC         = $(PFS_DIR)/sdmmc.c   $(PFS_DIR)/pff.c

COMMON_OBJ      = $(patsubst $(COMMON_DIR)/%.c,$(BUILD_DIR)/%.o,$(COMMON_SRC))
DHRY_OBJ        = $(patsubst $(DHRY_DIR)/%.c,$(BUILD_DIR)/%.o,$(DHRY_SRC))
CORE_OBJ        = $(patsubst $(CORE_DIR)/%.c,$(BUILD_DIR)/%.o,$(CORE_SRC))
FATFS_OBJ       = $(patsubst $(FATFS_DIR)/%.c,$(BUILD_DIR)/%.o,$(FATFS_SRC))
PFS_OBJ         = $(patsubst $(PFS_DIR)/%.c,$(BUILD_DIR)/%.o,$(PFS_SRC))

MAIN_PRJ_TO_BOOT= zputa_standalone_boot_in_bram
MAIN_PRJ_IN_BOOT= zputa_with_iocp_in_bram
MAIN_PRJ_TINY_BOOT=zputa_with_tiny_iocp_in_bram
MAIN_PRJ_RAM    = zputa_as_app_in_ram
MAIN_SRC        = zputa.c
MAIN_OBJ        = $(COMMON_OBJ) $(FATFS_OBJ) $(DHRY_OBJ) $(CORE_OBJ) $(patsubst %.c,$(BUILD_DIR)/%.o,$(MAIN_SRC))

# Commandline options for each tool.
# To disable use of a given instruction, prefix it with no-
ZPUOPTS         = -mloadsp \
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
ifeq ($(CPU), $(filter $(CPU),SMALL MEDIUM FLEX))
ZPUOPTS        += -mno-mult \
				  -mno-div \
				  -mno-mod \
				  -mno-neg
endif
ifeq ($(CPU), $(filter $(CPU),EVO))
ZPUOPTS        += -mmult \
	 	          -mdiv \
	          	  -mmod \
	          	  -mneg
endif

#CFLAGS         = -I. -I$(INCLUDE_DIR) -I$(COMMON_DIR)/.  -c -Os $(ZPUOPTS) -DPRINTF_HEX_ONLY -DDISABLE_PRINTF # -DDISABLE_UART_TX -DDISABLE_UART_RX
CFLAGS          = -I. -I$(COMMON_DIR) -I$(FATFS_DIR) -I$(DHRY_DIR) -I$(CORE_DIR) -I$(INCLUDE_DIR) -c -Os -ffunction-sections -fdata-sections $(ZPUOPTS) -DZPU -DZPUTA -DZPUTA_BASEADDR=$(ZPUTA_BASEADDR) -DZPUTA_APPADDR=$(ZPUTA_APPADDR)
# Enable debug output.
OFLAGS         += -DDEBUG
# Assume loadb as implemented in hardware or software (time penalty).
OFLAGS         += -DUSELOADB
# Dont allow an initialised DATA segment so binary can be located in ROM.
	#OFLAGS += -DUSE_BOOT_ROM
# Remove functionality to create a minimal system for limited space.
	#OFLAGS += -DMINIMUM_FUNCTIONALITY
# Enable CoreMark Test
#OFLAGS         += -DCOREMARK_TEST
# Enable Dhrystone Test
#OFLAGS         += -DDHRYSTONE_TEST
# Enable SD Card functionality
OFLAGS         += -DUSE_SDCARD
FLAGS_STR = -DFLAGS_STR="$(CFLAGS)"
LFLAGS          = -nostartfiles -Wl,--gc-sections -Wl,--relax -Os
#
# Assembler flags.
ASFLAGS         = -I. -I$(COMMON_DIR) -I$(INCLUDE_DIR) -I$(STARTUP_DIR) --defsym ZPUTA_BASEADDR=$(ZPUTA_BASEADDR) --defsym ZPUTA_APPADDR=$(ZPUTA_APPADDR)
#

# Our target.
all: $(BUILD_DIR) $(MAIN_PRJ_TO_BOOT) $(MAIN_PRJ_IN_BOOT) $(MAIN_PRJ_TINY_BOOT) $(MAIN_PRJ_RAM) $(ROMGEN)
#
$(MAIN_PRJ_TO_BOOT): $(BUILD_DIR) $(MAIN_PRJ_TO_BOOT).bin $(MAIN_PRJ_TO_BOOT).srec $(MAIN_PRJ_TO_BOOT).rpt $(MAIN_PRJ_TO_BOOT).lss $(MAIN_PRJ_TO_BOOT).dmp $(MAIN_PRJ_TO_BOOT)_BOOTROM.vhd $(MAIN_PRJ_TO_BOOT)_COMBINEDBOOTROM.vhd $(MAIN_PRJ_TO_BOOT)_BOOTBRAM.vhd
#
$(MAIN_PRJ_IN_BOOT): $(BUILD_DIR) $(MAIN_PRJ_IN_BOOT).bin $(MAIN_PRJ_IN_BOOT).srec $(MAIN_PRJ_IN_BOOT).rpt $(MAIN_PRJ_IN_BOOT).lss $(MAIN_PRJ_IN_BOOT).dmp $(MAIN_PRJ_IN_BOOT)_BOOTROM.vhd $(MAIN_PRJ_IN_BOOT)_COMBINEDBOOTBRAM.vhd
#
$(MAIN_PRJ_TINY_BOOT): $(BUILD_DIR) $(MAIN_PRJ_TINY_BOOT).bin $(MAIN_PRJ_TINY_BOOT).rpt $(MAIN_PRJ_TINY_BOOT).lss $(MAIN_PRJ_TINY_BOOT).dmp
#
#$(MAIN_PRJ_RAM): $(BUILD_DIR) $(MAIN_PRJ_RAM).bin $(MAIN_PRJ_RAM).srec $(MAIN_PRJ_RAM).rpt $(MAIN_PRJ_RAM).lss $(MAIN_PRJ_RAM).dmp $(MAIN_PRJ_RAM)_APPRAM.vhd $(MAIN_PRJ_RAM)_COMBINEDAPPRAM.vhd
$(MAIN_PRJ_RAM): $(BUILD_DIR) $(MAIN_PRJ_RAM).bin $(MAIN_PRJ_RAM).srec $(MAIN_PRJ_RAM).rpt $(MAIN_PRJ_RAM).lss $(MAIN_PRJ_RAM).dmp $(MAIN_PRJ_RAM)_COMBINEDAPPRAM.vhd

clean:
	rm -f $(BUILD_DIR)/*.o *.hex *.lss *.elf *.map *.lst *.srec $(MAIN_PRJ_TO_BOOT) $(MAIN_PRJ_IN_BOOT).rom $(MAIN_PRJ_TINY_BOOT).rom $(MAIN_PRJ_RAM) *~ */*.o *.bin *.srec *.dmp *.vhd *.rpt


# Convert ELF binary to bin file.
%.bin: %.elf
	@$(CP) -O binary $< $@

# Convert ELF to srec format for serial upload.
%.srec: %.elf
	@$(CP) -O srec $< $@

%.rpt: %.elf
	@echo ""
	@echo >$@ -n  "Start of code:\t"
	@$(DUMP) -x $< | grep >>$@ _ramstart
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
	@$(DUMP) -x $< | grep >>$@ _ramend
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

# Put the boot code and app code into a ROM compatible with the Small, Medium and Flex CPUś
%_BOOTROM.vhd: %.bin $(ROMGEN)
	@sed 's/dualportram/BootROM/' >ZPUTA_BootROM.vhd <$(RTL_DIR)/rom_prologue.vhd
	@$(ROMGEN) 4 $*.bin 0 > ROMCODE.dat
	@cat ROMCODE.dat $(RTL_DIR)/rom_epilogue.vhd >> ZPUTA_BootROM.vhd
	@cp ZPUTA_BootROM.vhd $(RTL_DIR)/
	@rm ROMCOD*.dat ZPUTA_BootROM.vhd
	@echo "ZPUTA_BootROM.vhd updated."

%_COMBINEDBOOTROM.vhd: %.bin $(ROMGEN)
	@sed 's/dualportram/BootROM/' >IOCP_ZPUTA_BootROM.vhd <$(RTL_DIR)/rom_prologue.vhd
	@$(ROMGEN) 4 $(IOCPDIR)/iocp.bin 0 > ROMCODE.dat
	@$(ROMGEN) 4 $*.bin 2048 > APPCODE.dat
	@cat ROMCODE.dat APPCODE.dat $(RTL_DIR)/rom_epilogue.vhd >> IOCP_ZPUTA_BootROM.vhd
	@cp IOCP_ZPUTA_BootROM.vhd $(RTL_DIR)/
	@rm ROMCOD*.dat APPCODE*.dat IOCP_ZPUTA_BootROM.vhd
	@echo "IOCP_ZPUTA_BootROM.vhd updated."

# Put the boot code into a BRAM used for boot code.
%_BOOTBRAM.vhd: %.bin $(ROMGEN)
	@sed 's/byteaddr_dp_32bit_bram/DualPortBootBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_dp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BA $*.bin /tmp/zpu_work.tmp 0 > ZPUTA_DualPortBootBRAM.vhd
	@cp ZPUTA_DualPortBootBRAM.vhd $(RTL_DIR)/
	@sed 's/byteaddr_sp_32bit_bram/SinglePortBootBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_sp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BA $*.bin /tmp/zpu_work.tmp 0 > ZPUTA_SinglePortBootBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp ZPUTA_SinglePortBootBRAM.vhd $(RTL_DIR)/
	@rm ZPUTA_DualPortBootBRAM.vhd ZPUTA_SinglePortBootBRAM.vhd
	@echo "ZPUTA_DualPortBootBRAM.vhd and ZPUTA_SinglePortBootBRAM updated."
	@echo ""

# Put the boot code and app code into a BRAM used for both boot code and application, ie. one block of BRAM.
%_COMBINEDBOOTBRAM.vhd: %.bin $(ROMGEN)
	@sed 's/byteaddr_dp_32bit_bram/DualPortBootBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_dp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BC $(IOCPDIR)/iocp.bin 0 $*.bin 2048 /tmp/zpu_work.tmp > IOCP_ZPUTA_DualPortBootBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp IOCP_ZPUTA_DualPortBootBRAM.vhd $(RTL_DIR)/
	@sed 's/byteaddr_sp_32bit_bram/SinglePortBootBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_sp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BC $(IOCPDIR)/iocp.bin 0 $*.bin 2048 /tmp/zpu_work.tmp > IOCP_ZPUTA_SinglePortBootBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp IOCP_ZPUTA_SinglePortBootBRAM.vhd $(RTL_DIR)/
	@rm IOCP_ZPUTA_DualPortBootBRAM.vhd IOCP_ZPUTA_SinglePortBootBRAM.vhd
	@echo "IOCP_ZPUTA_DualPortBootBRAM.vhd and IOCP_ZPUTA_SinglePortBootBRAM updated."
	@echo ""

# Put the app code into a seperate BRAM instantiation file, used when a 2nd block of App BRAM is created seperate to the boot BRAM and requires to be preloaded.
%_APPRAM.vhd: %.bin $(ROMGEN)
	@sed 's/byteaddr_sp_32bit_bram/SinglePortBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_sp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BA $*.bin /tmp/zpu_work.tmp 0 > ZPUTA_SinglePortBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp ZPUTA_SinglePortBRAM.vhd $(RTL_DIR)/
	@rm ZPUTA_SinglePortBRAM.vhd
	@echo "ZPUTA_SinglePortBRAM updated."

%_COMBINEDAPPRAM.vhd: %.bin $(ROMGEN)
	@sed 's/byteaddr_sp_32bit_bram/SinglePortBRAM/' >/tmp/zpu_work.tmp <$(RTL_DIR)/byteaddr_sp_32bit_bram_tmpl.vhd
	@$(ROMGEN) BA $*.bin /tmp/zpu_work.tmp 0 > IOCP_ZPUTA_SinglePortBRAM.vhd
	@rm -f /tmp/zpu_work.tmp
	@cp IOCP_ZPUTA_SinglePortBRAM.vhd $(RTL_DIR)/
	@rm IOCP_ZPUTA_SinglePortBRAM.vhd
	@echo "IOCP_ZPUTA_SinglePortBRAM updated."

# Link - this produces an ELF binary.
$(MAIN_PRJ_TO_BOOT).elf: $(ROMSTARTUP_OBJ) $(MAIN_OBJ)
	$(LD) $(LFLAGS) -T $(LINKMAPBOOTSTANDALONE) -o $@ $+ $(LIBS)

$(MAIN_PRJ_IN_BOOT).elf: $(RAMSTARTUP_OBJ) $(MAIN_OBJ)
	$(LD) $(LFLAGS) -T $(LINKMAPBOOTIOCP) -o $@ $+ $(LIBS)

$(MAIN_PRJ_TINY_BOOT).elf: $(RAMSTARTUP_OBJ) $(MAIN_OBJ)
	$(LD) $(LFLAGS) -T $(LINKMAPBOOTTINYIOCP) -o $@ $+ $(LIBS)

$(MAIN_PRJ_RAM).elf: $(RAMSTARTUP_OBJ) $(MAIN_OBJ)
	$(LD) $(LFLAGS) -T $(LINKMAPRAM) -o $@ $+ $(LIBS)

$(BUILD_DIR)/%.o: %.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: %.cpp Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: $(COMMON_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: $(DHRY_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: $(CORE_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) $(FLAGS_STR) -o $@ -c $<

$(BUILD_DIR)/%.o: $(FATFS_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS) -o $@ -c $<

$(BUILD_DIR)/%.o: $(PFS_DIR)/%.c Makefile
	$(CC) $(CFLAGS) $(OFLAGS)  -o $@ -c $<

$(BUILD_DIR)/%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/%.o: $(STARTUP_DIR)/%.s
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir $(BUILD_DIR)

