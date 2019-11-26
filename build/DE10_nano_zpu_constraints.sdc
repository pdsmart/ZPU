## Generated SDC file "hello_led.out.sdc"

## Copyright (C) 1991-2011 Altera Corporation
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, Altera MegaCore Function License 
## Agreement, or other applicable license agreement, including, 
## without limitation, that your use is for the sole purpose of 
## programming logic devices manufactured by Altera and sold by 
## Altera or its authorized distributors.  Please refer to the 
## applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 11.1 Build 216 11/23/2011 Service Pack 1 SJ Web Edition"

## DATE    "Fri Jul 06 23:05:47 2012"

##
## DEVICE  "EP3C25Q240C8"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3


#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clk_50} -period 20.000 -waveform { 0.000 0.500 } [get_ports {CLOCK_50}]


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {SYSCLK} -source [get_ports {CLOCK_50}] -duty_cycle 50.000 -multiply_by 2 -master_clock {clk_50} [get_nets {mypll|altpll_component|auto_generated|wire_generic_pll1_outclk}] 
#create_generated_clock -name {MEMCLK} -source [get_ports {CLOCK_50}] -duty_cycle 50.000 -phase 0 -multiply_by 4 -master_clock {clk_50} [get_nets {mypll|altpll_component|auto_generated|wire_generic_pll2_outclk}] 


#**************************************************************
# Set Clock Latency
#**************************************************************


#**************************************************************
# Set Clock Uncertainty
#**************************************************************

#set_clock_uncertainty -rise_from [get_clocks {MEMCLK}] -rise_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {MEMCLK}] -rise_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -rise_from [get_clocks {MEMCLK}] -fall_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {MEMCLK}] -fall_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {MEMCLK}] -rise_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {MEMCLK}] -rise_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {MEMCLK}] -fall_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {MEMCLK}] -fall_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -rise_to [get_clocks {MEMCLK}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -rise_to [get_clocks {MEMCLK}] -hold 0.060  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -fall_to [get_clocks {MEMCLK}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -fall_to [get_clocks {MEMCLK}] -hold 0.060  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -rise_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -rise_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -fall_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {SYSCLK}] -fall_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -rise_to [get_clocks {MEMCLK}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -rise_to [get_clocks {MEMCLK}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -fall_to [get_clocks {MEMCLK}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -fall_to [get_clocks {MEMCLK}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -rise_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -rise_to [get_clocks {SYSCLK}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -fall_to [get_clocks {SYSCLK}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {SYSCLK}] -fall_to [get_clocks {SYSCLK}] -hold 0.060  
derive_clock_uncertainty


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

set_false_path -from [get_keepers {KEY*}] 
set_false_path -from [get_keepers {SW*}] 
#set_false_path -from [get_cells {myVirtualToplevel|RESET_n}]


#**************************************************************
# Set Multicycle Path
#**************************************************************

#set_multicycle_path -setup -start -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] 1
#set_multicycle_path -hold -start -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] 0

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
