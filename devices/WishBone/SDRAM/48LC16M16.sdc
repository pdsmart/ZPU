# ------------------------------------------------------------------------------
# Constraints definition original author:
#   8/19/2014 D. W. Hawkings (dwh@ovro.caltech.edu)
# Adapted and enhanced for the Micron 48LC16M16 SDRAM by Philip Smart Dec 2019.
# ------------------------------------------------------------------------------
derive_pll_clocks

# -----------------------------------------------------------------
# SDRAM Clock
# Set these variables to the system and memory clock PLL paths for
# your board.
# -----------------------------------------------------------------
set sysclk_pll "mypll|altpll_component|auto_generated|generic_pll1~PLL_OUTPUT_COUNTER|divclk"
set memclk_pll "mypll|altpll_component|auto_generated|generic_pll2~PLL_OUTPUT_COUNTER|divclk"
create_generated_clock -name SDRAM_CLK -source $memclk_pll [get_ports {SDRAM_CLK}]
derive_clock_uncertainty

# -----------------------------------------------------------------
# SDRAM Constraints
# -----------------------------------------------------------------
#
# SDRAM timing parameters
#
# Generally, the command/address/data all have the same setup/hold
# time.
#
# SDRAM clock can lead System clock by min:
#     tlead = tcoutmin(FPGA) – th(SDRAM)
#
# SDRAM clock can lag System clock by min:
#     tlag  = toh(SDRAM) – th(FPGA)
#
# tSU = Data Setup time (ie. tDS, tAS) on falling edge.
# tH  = Hold time (ie. tDH, tAH) for SDRAM.
# tCOUT (min) = Data out hold time (ie. tOH)
# tCOUT (max) = Access time for CL in use (ie. tAC3).
#
set sdram_tsu       1.5
set sdram_th        0.8
set sdram_tco_min   3.0
set sdram_tco_max   5.4

# FPGA timing constraints
set sdram_input_delay_min        $sdram_tco_min
set sdram_input_delay_max        $sdram_tco_max
set sdram_output_delay_min      -$sdram_th
set sdram_output_delay_max       $sdram_tsu

# PLL to FPGA output (clear the unconstrained path warning)
#set_min_delay -from $memclk_pll -to [get_ports {SDRAM_CLK}] 1
#set_max_delay -from $memclk_pll -to [get_ports {SDRAM_CLK}] 6

# FPGA Outputs
set sdram_outputs [get_ports {
	SDRAM_CKE
	SDRAM_CS
	SDRAM_RAS
	SDRAM_CAS
	SDRAM_WE
	SDRAM_DQM[*]
	SDRAM_BA[*]
	SDRAM_ADDR[*]
	SDRAM_DQ[*]
}]
set_output_delay -clock SDRAM_CLK -min $sdram_output_delay_min $sdram_outputs
set_output_delay -clock SDRAM_CLK -max $sdram_output_delay_max $sdram_outputs

# FPGA Inputs
set sdram_inputs [get_ports {
	SDRAM_DQ[*]
}]
set_input_delay -clock SDRAM_CLK -min $sdram_input_delay_min $sdram_inputs
set_input_delay -clock SDRAM_CLK -max $sdram_input_delay_max $sdram_inputs

# -----------------------------------------------------------------
# SDRAM-to-FPGA multi-cycle constraint
# -----------------------------------------------------------------

# The PLL is configured so that SDRAM clock leads the system
# clock by ~90-degrees (0.25 period or 2.5ns for 100MHz clock).
# This will need changing for different clocks, in the PLL
# RTL file and the SoC contraints file.

# The following multi-cycle constraint declares to TimeQuest that
# the path between the SDRAM_CLK and the System Clock can be an
# extra clock period to the read path to ensure that the latch
# clock that occurs 1.25 periods after the launch clock is used in
# the timing analysis.
#
set_multicycle_path -setup -end -from SDRAM_CLK -to $sysclk_pll 2
