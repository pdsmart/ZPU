## Generated SDC file "E115_zpu.out.sdc"

## Copyright (C) 2017  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel FPGA IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Intel and sold by Intel or its authorized distributors.  Please
## refer to the applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 17.1.1 Internal Build 593 12/11/2017 SJ Standard Edition"

## DATE    "Sat Jun 22 23:32:00 2019"

##
## DEVICE  "EP4CE115F23I7"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clk_12} -period 83.333 -waveform { 0.000 0.500 } [get_ports {CLOCK_12M}]


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {SYSCLK} -source [get_ports {CLOCK_12M}] -duty_cycle 50.000 -multiply_by 25 -divide_by 3 -master_clock {clk_12} [get_nets {mypll|altpll_component|_clk0}] 
create_generated_clock -name {MEMCLK} -source [get_ports {CLOCK_12M}] -duty_cycle 50.000 -multiply_by 50 -divide_by 3 -master_clock {clk_12} [get_nets {mypll|altpll_component|_clk1}] 

#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

derive_clock_uncertainty
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -rise_to [get_clocks {SYSCLK}]  0.020  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -fall_to [get_clocks {SYSCLK}]  0.020  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -rise_to [get_clocks {SYSCLK}]  0.020  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -fall_to [get_clocks {SYSCLK}]  0.020


#**************************************************************
# Set Input Delay
#**************************************************************

# Delays for async signals - not necessary, but might as well avoid
# having unconstrained ports in the design
#set_input_delay -clock sysclk -min 0.5 [get_ports {UART_RXD}]
#set_input_delay -clock sysclk -max 0.5 [get_ports {UART_RXD}]


#**************************************************************
# Set Output Delay
#**************************************************************

#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[0]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[1]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[2]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[3]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[4]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[5]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[6]}]
#set_output_delay -add_delay  -clock [get_clocks {sysclk}]  0.500 [get_ports {LED[7]}]


#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_keepers {USER_BTN*}] 
#set_false_path -from [get_keepers {SW*}] 
#set_false_path -from [get_cells {myVirtualToplevel|RESET_n}]


#**************************************************************
# Set Multicycle Path
#**************************************************************

set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] -setup -start 1
set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] -hold -start 0
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|cacheFetchIdx[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|TOS.word[*]}] -setup -start 2
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|cacheFetchIdx[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|TOS.word[*]}] -hold -start 0
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|cacheL1[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|TOS.word[*]}] -setup -start 1
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|cacheL1[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|TOS.word[*]}] -hold -start 0
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxNOS[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|TOS.word[*]}] -setup -start 1
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxNOS[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|TOS.word[*]}] -hold -start 0

#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

