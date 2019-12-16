derive_pll_clocks

#create_generated_clock -source [get_pins -compatibility_mode {*|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
#{*mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk}] \

#create_generated_clock -source [get_pins -compatibility_mode {mypll|altpll_component|pll|clk[1]}] \
#                       -name MEMCLK [get_ports {MEMCLK}]
#create_generated_clock -source [get_pins -compatibility_mode {mypll|altpll_component|pll|clk[1]}] -multiply_by 1 \
#                       -name MEMCLK [get_ports {MEMCLK}]
#create_generated_clock -name {MEMCLK} -source [get_ports {CLOCK_12M}] -duty_cycle 50.000 -multiply_by 25 -divide_by 2 -master_clock {clk_12} [get_nets {mypll|altpll_component|_clk1}] 
#create_generated_clock -name {MEMCLK} -source [get_pins -compatibility_mode {mypll|altpll_component|pll|clk[1]}] -master_clock {MEMCLK} [get_ports {MEMCLK}]

derive_clock_uncertainty

# Set acceptable delays for SDRAM chip (See correspondent chip datasheet) 
set_input_delay -max -clock MEMCLK 6.4ns [get_ports SDRAM_DQ[*]]
set_input_delay -min -clock MEMCLK 3.7ns [get_ports SDRAM_DQ[*]]

#                    -to [get_clocks {*|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
#set_multicycle_path -from [get_clocks {MEMCLK}] \
#                    -to [get_clocks {SYSCLK}] \
#                     -setup 2


set_output_delay -max -clock MEMCLK 1.6ns [get_ports {SDRAM_D* SDRAM_ADDR* SDRAM_BA* SDRAM_CS SDRAM_WE SDRAM_RAS SDRAM_CAS SDRAM_CKE}]
set_output_delay -min -clock MEMCLK -0.9ns [get_ports {SDRAM_D* SDRAM_ADDR* SDRAM_BA* SDRAM_CS SDRAM_WE SDRAM_RAS SDRAM_CAS SDRAM_CKE}]
