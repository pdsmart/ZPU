## Generated SDC file "QMV_zpu.out.sdc"

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
## DEVICE  "5CEFA2F23C8"
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

#create_generated_clock -name {SYSCLK} -source [get_ports {CLOCK_50}] -duty_cycle 50.000 -multiply_by 2 -divide_by 1 -master_clock {clk_50} [get_nets {mypll|altpll_component|_clk0}] 
#create_generated_clock -name {MEMCLK} -source [get_ports {CLOCK_50}] -duty_cycle 50.000 -multiply_by 4 -divide_by 1 -master_clock {clk_50} [get_nets {mypll|altpll_component|_clk1}] 
create_generated_clock -name {mypll|altpll_component|auto_generated|generic_pll1~FRACTIONAL_PLL|vcoph[0]} -source [get_pins {mypll|altpll_component|auto_generated|generic_pll1~FRACTIONAL_PLL|refclkin}] -duty_cycle 50/1 -multiply_by 12 -divide_by 2 -master_clock {clk_50} [get_pins {mypll|altpll_component|auto_generated|generic_pll1~FRACTIONAL_PLL|vcoph[0]}] 
create_generated_clock -name {mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 4 -master_clock {mypll|altpll_component|auto_generated|generic_pll1~FRACTIONAL_PLL|vcoph[0]} [get_pins {mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk}] 
#create_generated_clock -name {mypll|altpll_component|auto_generated|generic_pll2~PLL_OUTPUT_COUNTER|divclk} -source [get_pins {mypll|altpll_component|auto_generated|generic_pll2~PLL_OUTPUT_COUNTER|vco0ph[0]}] -duty_cycle 50/1 -multiply_by 1 -divide_by 4 -master_clock {mypll|altpll_component|auto_generated|generic_pll1~FRACTIONAL_PLL|vcoph[0]} [get_pins {mypll|altpll_component|auto_generated|generic_pll2~PLL_OUTPUT_COUNTER|divclk}] 

#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

derive_clock_uncertainty
#set_clock_uncertainty -rise_from [get_clocks {clk_50}] -rise_to [get_clocks {clk_50}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {clk_50}] -rise_to [get_clocks {clk_50}] -hold 0.060  
#set_clock_uncertainty -rise_from [get_clocks {clk_50}] -fall_to [get_clocks {clk_50}] -setup 0.080  
#set_clock_uncertainty -rise_from [get_clocks {clk_50}] -fall_to [get_clocks {clk_50}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {clk_50}] -rise_to [get_clocks {clk_50}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {clk_50}] -rise_to [get_clocks {clk_50}] -hold 0.060  
#set_clock_uncertainty -fall_from [get_clocks {clk_50}] -fall_to [get_clocks {clk_50}] -setup 0.080  
#set_clock_uncertainty -fall_from [get_clocks {clk_50}] -fall_to [get_clocks {clk_50}] -hold 0.060


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



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_keepers {KEY*}] 
#set_false_path -from [get_keepers {SW*}] 


#**************************************************************
# Set Multicycle Path
#**************************************************************

#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] -setup -start 1
#set_multicycle_path -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] -hold -start 0
set_multicycle_path -setup -start -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] 1
set_multicycle_path -hold -start -from [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|pc[*]}] -to [get_keepers {zpu_soc:myVirtualToplevel|zpu_core_evo:\ZPUEVO:ZPU0|mxFifo[*]}] 0

#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

