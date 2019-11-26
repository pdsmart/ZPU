derive_pll_clocks

#create_generated_clock -source [get_pins -compatibility_mode {*|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
create_generated_clock -source [get_pins -compatibility_mode {*mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk}] \
                       -name SDRAM_CLK [get_ports {SDRAM_CLK}]

derive_clock_uncertainty

# Set acceptable delays for SDRAM chip (See correspondent chip datasheet) 
set_input_delay -max -clock SDRAM_CLK 6.4ns [get_ports SDRAM_DQ[*]]
set_input_delay -min -clock SDRAM_CLK 3.7ns [get_ports SDRAM_DQ[*]]

#                    -to [get_clocks {*|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set_multicycle_path -from [get_clocks {SDRAM_CLK}] \
                    -to [get_clocks {*mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk}] \
                                                  -setup 2

set_output_delay -max -clock SDRAM_CLK 1.6ns [get_ports {SDRAM_D* SDRAM_ADDR* SDRAM_BA* SDRAM_CS SDRAM_WE SDRAM_RAS SDRAM_CAS SDRAM_CKE}]
set_output_delay -min -clock SDRAM_CLK -0.9ns [get_ports {SDRAM_D* SDRAM_ADDR* SDRAM_BA* SDRAM_CS SDRAM_WE SDRAM_RAS SDRAM_CAS SDRAM_CKE}]