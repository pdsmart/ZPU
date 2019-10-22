#########################################################################################################
##
## Name:            Makefile
## Created:         June 2019
## Author(s):       Philip Smart
## Description:     ZPU Makefile
##                  This script builds the ZPU test images and should be used as a basis for main
##                  project builds.
##
## Credits:         
## Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
##
## History:         June 2019   - Initial script written.
##
#########################################################################################################
## This source file is free software: you can redistribute it and#or modify
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

DE10_IP     = 192.168.10.1
DE10_USER   = root
DE10_PWD    = 1
ROOT        = ../

# Build utilites
QUARTUS_SH  = quartus_sh
QUARTUS_CPF = quartus_cpf
TEE         = tee
ECHO        = echo
MV          = mv
GREP        = grep
RM          = rm
CC			= CC $(CINCLUDES)
AR			= ar
LD			= ld

# Build flags
SH_FLAGS    = --flow compile
CPF_FLAGS   = -c -o bitstream_compression=on
MSG_FILTER  = "Error\|success"
# MSG_FILTER  = "Info\|Warning\|Error\|success"
# MSG_FILTER  = "Info\|Warning\|Error\|success"
# MSG_FILTER  = "Info\|Warning\|Error\|success"

SOC         = $(ROOT)/zpu_soc.vhd $(ROOT)/zpu_soc_pkg.vhd
ZPU_EVO     = $(ROOT)/cpu/zpu_core_evo.vhd $(ROOT)/cpu/zpu_pkg.vhd

.PHONY:	all
all: DE10_nano_SMALL DE10_nano_MEDIUM DE10_nano_FLEX DE10_nano_EVO DE10_nano_EVO_MINIMAL E115_SMALL E115_MEDIUM E115_FLEX E115_EVO E115_EVO_MINIMAL
DE10_nano: DE10_nano_SMALL DE10_nano_MEDIUM DE10_nano_FLEX DE10_nano_EVO DE10_nano_EVO_MINIMAL
E115: E115_SMALL E115_MEDIUM E115_FLEX E115_EVO E115_EVO_MINIMAL
SMALL: DE10_nano_SMALL E115_SMALL
MEDIUM: DE10_nano_MEDIUM E115_MEDIUM
FLEX: DE10_nano_FLEX E115_FLEX
EVO: DE10_nano_EVO E115_EVO
EVO_MINIMAL: DE10_nano_EVO_MINIMAL E115_EVO_MINIMAL

DE10_nano_SMALL:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_SMALL                :     integer    := [01]/ZPU_SMALL                :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) DE10_nano_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) DE10_nano_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

DE10_nano_MEDIUM:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_MEDIUM               :     integer    := [01]/ZPU_MEDIUM               :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) DE10_nano_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) DE10_nano_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

DE10_nano_FLEX:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_FLEX                 :     integer    := [01]/ZPU_FLEX                 :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) DE10_nano_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) DE10_nano_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

DE10_nano_EVO:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_EVO                  :     integer    := [01]/ZPU_EVO                  :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) DE10_nano_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) DE10_nano_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

DE10_nano_EVO_MINIMAL:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_EVO_MINIMAL          :     integer    := [01]/ZPU_EVO_MINIMAL          :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) DE10_nano_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) DE10_nano_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

E115_SMALL:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_SMALL                :     integer    := [01]/ZPU_SMALL                :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) E115_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) E115_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

E115_MEDIUM:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_MEDIUM               :     integer    := [01]/ZPU_MEDIUM               :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) E115_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) E115_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

E115_FLEX:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_FLEX                 :     integer    := [01]/ZPU_FLEX                 :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) E115_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) E115_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

E115_EVO:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_EVO                  :     integer    := [01]/ZPU_EVO                  :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) E115_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) E115_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

E115_EVO_MINIMAL:
	@cat $(ROOT)/zpu_soc_pkg.tmpl.vhd | sed 's/ZPU_EVO_MINIMAL          :     integer    := [01]/ZPU_EVO_MINIMAL          :     integer    := 1/g' \
	  > $(ROOT)/zpu_soc_pkg.vhd
	@$(ECHO) "Compiling $@..."
	@$(QUARTUS_SH) $(SH_FLAGS) E115_zpu.qpf 2> /dev/null | $(TEE) $@.log | $(GREP) -i $(MSG_FILTER)
	@$(MV) E115_zpu.sof $@.sof
	@$(QUARTUS_CPF) $(CPF_FLAGS) $@.sof $@.rbf 2> /dev/null | $(TEE) -a $@.log | $(GREP) -i $(MSG_FILTER)
	@$(ECHO) "$@.sof and $@.rbf generated..."

clean:
	@$(ECHO) "Removing all temporary files..."
	@$(RM) -fr c5_pin_model_dump.txt ./db ./simulation DE10_nano_zpu.asm.rpt DE10_nano_zpu.done DE10_nano_zpu.fit.rpt DE10_nano_zpu.fit.smsg DE10_nano_zpu.fit.summary DE10_nano_zpu.flow.rpt DE10_nano_zpu.jdi DE10_nano_zpu.map.rpt DE10_nano_zpu.map.smsg DE10_nano_zpu.map.summary DE10_nano_zpu.pin DE10_nano_zpu.rbf DE10_nano_zpu.sld DE10_nano_zpu.sof DE10_nano_zpu.sta.rpt DE10_nano_zpu.sta.summary ./incremental_db qmegawiz_errors_log.txt DE10*.log DE10_nano*.rbf DE10_nano*.sof DE10_nano*.sta.smsg 
	@$(RM) -fr c5_pin_model_dump.txt ./db E115_zpu.asm.rpt E115_zpu.done E115_zpu.fit.rpt E115_zpu.fit.smsg E115_zpu.fit.summary E115_zpu.flow.rpt E115_zpu.jdi E115_zpu.map.rpt E115_zpu.map.smsg E115_zpu.map.summary E115_zpu.pin E115_zpu.rbf E115_zpu.sld E115_zpu.sof E115_zpu.sta.rpt E115_zpu.sta.summary ./incremental_db qmegawiz_errors_log.txt E115_zpu.pof E115*.log E115*.rbf E115*.sof E115*.sta.smsg
	@$(RM) -fr c5_pin_model_dump.txt ./db CYC1000_zpu.asm.rpt CYC1000_zpu.done CYC1000_zpu.fit.rpt CYC1000_zpu.fit.smsg CYC1000_zpu.fit.summary CYC1000_zpu.flow.rpt CYC1000_zpu.jdi CYC1000_zpu.map.rpt CYC1000_zpu.map.smsg CYC1000_zpu.map.summary CYC1000_zpu.pin CYC1000_zpu.rbf CYC1000_zpu.sld CYC1000_zpu.sof CYC1000_zpu.sta.rpt CYC1000_zpu.sta.summary ./incremental_db qmegawiz_errors_log.txt CYC1000_zpu.pof CYC1000*.log CYC1000*.rbf CYC1000*.sof CYC1000*.sta.smsg
	@$(RM) -fr c5_pin_model_dump.txt ./db QMV_zpu.asm.rpt QMV_zpu.done QMV_zpu.fit.rpt QMV_zpu.fit.smsg QMV_zpu.fit.summary QMV_zpu.flow.rpt QMV_zpu.jdi QMV_zpu.map.rpt QMV_zpu.map.smsg QMV_zpu.map.summary QMV_zpu.pin QMV_zpu.rbf QMV_zpu.sld QMV_zpu.sof QMV_zpu.sta.rpt QMV_zpu.sta.summary ./incremental_db qmegawiz_errors_log.txt QMV_zpu.pof QMV*.log QMV*.rbf QMV*.sof QMV*.sta.smsg
	@$(RM) -fr output_files
