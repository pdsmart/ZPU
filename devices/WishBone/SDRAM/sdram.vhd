---------------------------------------------------------------------------------------------------------
--
-- Name:            sdram.vhd
-- Created:         September 2019
-- Original Author: Stephen J. Leary 2013-2014 
-- VHDL Author:     Philip Smart
-- Description:     Original module written by Stephen J. Leary 2013-2014 in Verilog for use with the
--                  MT48LC16M16 chip.
--                  It has been translated into VHDL and undergoing extensive modifications to work
--                  with the ZPU EVO processor, specifically burst tuning to enhance L2 Cache Fill
--                  performance.
-- Credits:         
-- Copyright:       Copyright (c) 2013-2014, Stephen J. Leary, All rights reserved.
--                  VHDL translation and enhancements (c) 2019 Philip Smart <philip.smart@net2net.org>
--
-- History:         September 2019  - Initial module based on translaction of Stephen J. Leary's Verilog
--                                    source code.
--
---------------------------------------------------------------------------------------------------------
-- This source file is free software: you can redistribute it and-or modify
-- it under the terms of the GNU General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This source file is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http:--www.gnu.org-licenses->.
---------------------------------------------------------------------------------------------------------
library ieee;
library pkgs;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.zpu_soc_pkg.all;
use work.zpu_pkg.all;

entity SDRAM is
    generic (
        MAX_DATACACHE_BITS    : integer := 4                                      -- Maximum size in addr bits of 32bit datacache for burst transactions.
    );
    port (
        -- SDRAM Interface
        SD_CLK                : in    std_logic;                                  -- sdram is accessed at 128MHz
        SD_RST                : in    std_logic;                                  -- reset the sdram controller.
        SD_CKE                : out   std_logic;                                  -- clock enable.
        SD_DQ                 : inout std_logic_vector(15 downto 0);              -- 16 bit bidirectional data bus
        SD_ADDR               : out   std_logic_vector(12 downto 0);              -- 13 bit multiplexed address bus
        SD_DQM                : out   std_logic_vector(1 downto 0);               -- two byte masks
        SD_BA                 : out   std_logic_vector(1 downto 0);               -- two banks
        SD_CS_n               : out   std_logic;                                  -- a single chip select
        SD_WE_n               : out   std_logic;                                  -- write enable
        SD_RAS_n              : out   std_logic;                                  -- row address select
        SD_CAS_n              : out   std_logic;                                  -- columns address select
        SD_READY              : out   std_logic;                                  -- sd ready.

        -- WishBone interface.
        WB_CLK                : in    std_logic;                                  -- Master clock at which the Wishbone interface operates.
        WB_DAT_I              : in    std_logic_vector(WORD_32BIT_RANGE);         -- Data input from Master
        WB_DAT_O              : out   std_logic_vector(WORD_32BIT_RANGE);         -- Data output to Master
        WB_ACK_O              : out   std_logic;
        WB_ADR_I              : in    std_logic_vector(23 downto 0);              -- lower 2 bits are ignored.
        WB_SEL_I              : in    std_logic_vector(3 downto 0);
        WB_CTI_I              : in    std_logic_vector(2 downto 0);               -- 000 Classic cycle, 001 Constant address burst cycle, 010 Incrementing burst cycle, 111 End-of-Burst

        WB_STB_I              : in    std_logic;
        WB_CYC_I              : in    std_logic;                                  -- cpu/chipset requests cycle
        WB_WE_I               : in    std_logic                                   -- cpu/chipset requests write   
    );
end SDRAM;

architecture Structure of SDRAM is

    -- Constants for register access.
    --
    constant RASCAS_DELAY     :       integer := 3;                               -- tRCD=20ns -> 2 cycles@100MHz
    constant RFC_DELAY        :       integer := 70;                              -- tRFC=66ns time in nS for a autorefresh to complete.
    constant RAM_CLK          :       integer := 100000000;

    -- Command table from the Micron datasheet.
    -- Name                         (Function)                                     CS#  RAS# CAS# WE# DQM ADDR      DQ
    -- COMMAND INHIBIT              (NOP)                                           H    X    X    X   X   X        X
    -- NO OPERATION                 (NOP)                                           L    H    H    H   X   X        X
    -- ACTIVE                       (select bank and activate row)                  L    L    H    H   X   Bank/row X
    -- READ                         (select bank and column, and start READ burst)  L    H    L    H   L/H Bank/col X
    -- WRITE                        (select bank and column, and start WRITE burst) L    H    L    L   L/H Bank/col Valid
    -- BURST TERMINATE                                                              L    H    H    L   X   X        Active
    -- PRECHARGE                    (Deactivate row in bank or banks)               L    L    H    L   X   Code     X
    -- AUTO REFRESH or SELF REFRESH (enter self refresh mode)                       L    L    L    H   X   X        X
    -- LOAD MODE REGISTER                                                           L    L    L    L   X   Op-code  X
    -- Write enable/output enable                                                   X    X    X    X   L   X        Active
    -- Write inhibit/output High-Z                                                  X    X    X    X   H   X        High-Z
    constant CMD_INHIBIT      :       std_logic_vector(3 downto 0) := "1111";
    constant CMD_NOP          :       std_logic_vector(3 downto 0) := "0111";
    constant CMD_ACTIVE       :       std_logic_vector(3 downto 0) := "0011";
    constant CMD_READ         :       std_logic_vector(3 downto 0) := "0101";
    constant CMD_WRITE        :       std_logic_vector(3 downto 0) := "0100";
    constant CMD_BURST_TERMINATE :    std_logic_vector(3 downto 0) := "0110";
    constant CMD_PRECHARGE    :       std_logic_vector(3 downto 0) := "0010";
    constant CMD_AUTO_REFRESH :       std_logic_vector(3 downto 0) := "0001";
    constant CMD_LOAD_MODE    :       std_logic_vector(3 downto 0) := "0000";

    -- Load Mode Register setting.
    -- 12:10  = Reserved            :
    -- 9      = Write Burst Mode    : 0 = Programmed Burst Length, 1 = Single Location Access
    -- 8:7    = Operating Mode      : 00 = Standard Operation, all other values reserved.
    -- 6:4    = CAS Latency         : 010 = 2, 011 = 3, all other values reserved.
    -- 3      = Burst Type          : 0 = Sequential, 1 = Interleaved.
    -- 2:0    = Burst Length        : When 000 = 1, 001 = 2, 010 = 4, 011 = 8, all others reserved except 111 when BT = 0 sets full page access.
    --                              | A12-A10 | A9        A8-A7  | A6 A5 A4 | A3Â      A2 A1 A0 |
    --                              | reserved| wr burst |reserved| CAS Ltncy|addr mode| burst len|
    constant WRITE_BURST_MODE :       std_logic := '1';
    constant OP_MODE          :       std_logic_vector(1 downto 0) := "00";
    constant CAS_LATENCY      :       std_logic_vector(2 downto 0) := "011";
    constant BURST_TYPE       :       std_logic := '0';
    constant BURST_LENGTH     :       std_logic_vector(2 downto 0) := "000";
    constant MODE             :       std_logic_vector(12 downto 0) := "000" & WRITE_BURST_MODE & OP_MODE & CAS_LATENCY & BURST_TYPE & BURST_LENGTH; 

    -- FSM Cycle States.
    constant CYCLE_PRECHARGE  :       integer := 0;                                                          -- 0
    constant CYCLE_RAS_START  :       integer := 3;                                                          -- 3
    constant CYCLE_RAS_NEXT   :       integer := CYCLE_RAS_START  + 1;                                       -- 4
    constant CYCLE_CAS0       :       integer := CYCLE_RAS_START  + RASCAS_DELAY;                            -- 3 + RASCAS_DELAY
    constant CYCLE_CAS1       :       integer := CYCLE_CAS0       + 1;                                       -- 4 + RASCAS_DELAY
    constant CYCLE_CAS2       :       integer := CYCLE_CAS1       + 1;                                       -- 5 + RASCAS_DELAY
    constant CYCLE_CAS3       :       integer := CYCLE_CAS2       + 1;                                       -- 6 + RASCAS_DELAY
    constant CYCLE_READ0      :       integer := CYCLE_CAS0       + to_integer(unsigned(CAS_LATENCY)) + 1;   -- 3 + RASCAS_DELAY + CAS_LATENCY
    constant CYCLE_READ1      :       integer := CYCLE_READ0      + 1;                                       -- 4 + RASCAS_DELAY + CAS_LATENCY
    constant CYCLE_READ2      :       integer := CYCLE_READ1      + 1;                                       -- 5 + RASCAS_DELAY + CAS_LATENCY
    constant CYCLE_READ3      :       integer := CYCLE_READ2      + 1;                                       -- 6 + RASCAS_DELAY + CAS_LATENCY
    constant CYCLE_END        :       integer := CYCLE_READ3      + 1;                                       -- 9 + RASCAS_DELAY + CAS_LATENCY
    constant CYCLE_RFSH_START :       integer := CYCLE_RAS_START;                                            -- 3
    constant CYCLE_RFSH_END   :       integer := CYCLE_RFSH_START + ((RFC_DELAY/RAM_CLK) * 10000000) + 1;    -- 3 + RFC_DELAY in clock ticks.

    -- Period in clock cycles between SDRAM refresh cycles.
    constant REFRESH_PERIOD   :       integer := (RAM_CLK / (64 * 8192)) - CYCLE_END;    

    type BankArray is array(natural range 0 to 3) of std_logic_vector(11 downto 0);

    -- Cache for holding burst reads to allow for differing speeds of WishBone Master.
    type DataCacheArray is array(natural range 0 to ((2**(MAX_DATACACHE_BITS))-1)) of std_logic_vector(WORD_32BIT_RANGE);
    signal readCache          :       DataCacheArray;
    attribute ramstyle        :       string;
    attribute ramstyle of readCache : signal is "logic";
    signal cacheReadAddr      :       unsigned(MAX_DATACACHE_BITS-1 downto 0);
    signal cacheWriteAddr     :       unsigned(MAX_DATACACHE_BITS-1 downto 0);

    signal sd_dat             :       std_logic_vector(31 downto 0);
    signal sd_dat_nxt         :       std_logic_vector(31 downto 0);
    signal sd_stb             :       std_logic;
    signal sd_we              :       std_logic;
    signal sd_cyc             :       std_logic;
    signal sd_burst           :       std_logic;
    signal sd_cycle           :       integer range 0 to 15;
    signal sd_done            :       std_logic;
    signal sd_cmd             :       std_logic_vector(3 downto 0);
    signal sd_refresh         :       unsigned(3 downto 0);
    signal sd_auto_refresh    :       std_logic;
    signal sd_req             :       std_logic_vector(2 downto 0);

    signal sd_in_rst          :       unsigned(7 downto 0);
    signal sd_rst_timer       :       unsigned(6 downto 0);
    signal sd_active_row      :       BankArray;
    signal sd_bank_active     :       std_logic_vector(1 downto 0);
    signal sd_bank            :       natural range 0 to 3;
    signal sd_row             :       std_logic_vector(11 downto 0);
    signal sd_reading         :       std_logic;
    signal sd_writing         :       std_logic;
    signal sd_rdy             :       std_logic;
    signal sd_mxadr           :       std_logic_vector(12 downto 0);              -- 13 bit multiplexed address bus
    signal sd_dout            :       std_logic_vector(15 downto 0);
    signal sd_din             :       std_logic_vector(15 downto 0);
    signal sd_done_last       :       std_logic;

    signal burst_mode         :       std_logic;
    signal can_burst          :       std_logic;

    signal wb_ack             :       std_logic;
    signal wb_burst           :       std_logic;

begin

    -- Tri-state control of the SDRAM data bus.
    process(sd_writing, SD_DQ, sd_dout)
    begin
        if (sd_writing = '0') then
            SD_DQ                                     <= (others => 'Z');
            sd_din                                    <= SD_DQ;
        else
            SD_DQ                                     <= sd_dout; 
            sd_din                                    <= SD_DQ;
        end if;
    end process;

    -- Main FSM for SDRAM control and refresh.
    process(SD_CLK, SD_RST)
    begin
        if (SD_RST = '1') then
            sd_rst_timer                              <= (others => '0'); -- 0 upto 127
            sd_in_rst                                 <= (others => '1'); -- 255 downto 0
            sd_mxadr                                  <= (others => '0');
            sd_auto_refresh                           <= '0';
            sd_bank_active                            <= (others => '0');
            sd_refresh                                <= (others => '0');
            sd_active_row                             <= ((others => '0'), (others => '0'), (others => '0'), (others => '0'));
            sd_rdy                                    <= '0';
            sd_cmd                                    <= CMD_AUTO_REFRESH;
            sd_stb                                    <= '0';
            sd_cyc                                    <= '0';
            sd_burst                                  <= '0';
            sd_we                                     <= '0';
            sd_cycle                                  <= 0;
            sd_done                                   <= '0';
            cacheWriteAddr                            <= (others => '0');

        elsif rising_edge(SD_CLK) then

            -- If no specific command given the default is NOP.
            sd_cmd                                    <= CMD_NOP;

            -- Initialisation on power up or reset. The SDRAM must be given at least 100uS to initialise and a fixed setup pattern applied.
            if (sd_rdy = '0') then
                sd_rst_timer                          <= sd_rst_timer + 1;
    
                -- 1uS timer.
                if (sd_rst_timer = RAM_CLK/1000000) then 
                    sd_rst_timer                      <= (others => '0'); 
                    sd_in_rst                         <= sd_in_rst - 1;        
                end if;
    
                -- Every 1uS check for the next init action.
                if (sd_rst_timer = 0) then 

                    -- 100uS wait, no action as the SDRAM starts up.
                    -- ie. 255 downto 155
    
                    -- Precharge all banks
                    if(sd_in_rst = 155) then
                        sd_cmd                        <= CMD_PRECHARGE;
                        sd_mxadr(10)                  <= '1';
                    end if;
    
                    -- Load the Mode register with our parameters.
                    if(sd_in_rst = 148 or sd_in_rst = 147) then
                        sd_cmd                        <= CMD_LOAD_MODE;
                        sd_mxadr                      <= MODE;
                    end if;

                    -- 2 auto refresh commands as specified in datasheet. The RFS time is 60nS, so using a 1uS timer, issue one after
                    -- the other.
                    if(sd_in_rst = 145 or sd_in_rst = 140) then
                        sd_cmd                        <= CMD_AUTO_REFRESH;
                    end if;
    
                    -- SDRAM ready.
                    if(sd_in_rst = 135) then
                        sd_rdy                        <= '1';
                    end if;
                end if;
            else
        
                -- bring the wishbone bus signal into the ram clock domain.
    
                sd_we                                 <= WB_WE_I;
                if (sd_req = "111") then 
                    sd_stb                            <= WB_STB_I;
                    sd_cyc                            <= WB_CYC_I;
                end if;
    
                sd_refresh                            <= sd_refresh + 1;
    
                -- Auto refresh. On timeout it kicks in so that 8192 auto refreshes are 
                -- issued in a 64ms period. Other bus operations are stalled during this period.
                if ((sd_refresh > REFRESH_PERIOD) and (sd_cycle = 0)) then 
                    sd_auto_refresh                   <= '1';
                    sd_refresh                        <= (others => '0');
                    sd_cmd                            <= CMD_PRECHARGE;
                    sd_mxadr(10)                      <= '1';
                    sd_bank_active                    <= (others => '0');
    
                -- In auto refresh period.
                elsif (sd_auto_refresh = '1') then 
    
                    -- while the cycle is active count.
                    sd_cycle                          <= sd_cycle +  1;
                    case (sd_cycle) is 
                        when CYCLE_RFSH_START =>
                            sd_cmd                    <= CMD_AUTO_REFRESH;
    
                        when CYCLE_RFSH_END =>
                            -- reset the count.
                            sd_auto_refresh           <= '0';
                            sd_cycle                  <= 0;

                        when others =>
                    end case;
    
                elsif (sd_cyc = '1' or (sd_cycle /= 0) or (sd_cycle = 0 and sd_req = "111")) then 
    
                    -- while the cycle is active count.
                    sd_cycle                          <= sd_cycle + 1;
                    case (sd_cycle) is

                        when CYCLE_PRECHARGE =>
                            -- If the bank is not open then no need to precharge, move onto RAS.
                            if (sd_bank_active(sd_bank) = '0') then
                                sd_cycle              <= CYCLE_RAS_START;

                            -- If the requested row is already active, go to CAS for immediate access to this row.
                            elsif (sd_active_row(sd_bank) = sd_row) then
                                sd_cycle              <= CYCLE_CAS0 - 1; -- FIXME: Why doesn't work without -1?

                            -- Otherwise we close out the open bank by issuing a PRECHARGE.
                            else 
                                sd_cmd                <= CMD_PRECHARGE;
                                sd_mxadr(10)          <= '0';
                                SD_BA                 <= std_logic_vector(to_unsigned(sd_bank, SD_BA'length));
                            end if;
    
                        -- Open the requested row.
                        when CYCLE_RAS_START =>
                            sd_cmd                    <= CMD_ACTIVE;
                            sd_mxadr                  <= '0' & sd_row;                                          -- 0 & Addr[20:9] presented to SDRAM as row address.
                            SD_BA                     <= std_logic_vector(to_unsigned(sd_bank, SD_BA'length));  -- Addr[22:21]
                            sd_active_row(sd_bank)    <= sd_row;                                                -- Store number of row being made active
                            sd_bank_active(sd_bank)   <= '1';                                                   -- Store flag to indicate which bank is being made active.
                    
                        when CYCLE_RAS_NEXT =>
                            sd_mxadr(12 downto 11)    <= "11";                                                  -- Set DQ to tri--state.
    
                        -- this is the first CAS cycle
                        when CYCLE_CAS0 =>
                            -- Process on a 32bit boundary, as this is a 16bit chip we need 2 accesses for a 32bit alignment.
                            sd_mxadr                  <= "0000" & WB_ADR_I(23) & WB_ADR_I(8 downto 2) & '0';    -- CAS address = Addr[23,8:2] accessing first 16bit location within the 32bit external alignment with no auto precharge
                            SD_BA                     <= std_logic_vector(to_unsigned(sd_bank, SD_BA'length));  -- Ensure bank is the correct one opened.
    
                            if (sd_reading = '1') then 
                                sd_cmd                <= CMD_READ;
                            elsif (sd_writing = '1') then 
                                sd_cmd                <= CMD_WRITE;
                                sd_mxadr(12 downto 11)<= not WB_SEL_I(1 downto 0);                              -- For writing, set DQM to the negated WB_SEL values, indicating which bytes to process. 
                                sd_dout               <= wb_dat_i(15 downto 0);                                 -- Assign corresponding data to the SDRAM databus.
                            end if;
    
                        when CYCLE_CAS1 =>
                            sd_mxadr                  <= "0000" & WB_ADR_I(23) & WB_ADR_I(8 downto 2) & '1';    -- As per CAS0 except we now access second 16bit location within the 32bit external alignment.
                            if (sd_reading = '1') then 
                                sd_cmd                <= CMD_READ;
                                if (burst_mode = '1' and can_burst = '1') then 
                                    sd_burst          <= '1'; 
                                end if;
                            elsif (sd_writing = '1') then 
                                sd_cmd                <= CMD_WRITE;
                                sd_mxadr(12 downto 11)<= not WB_SEL_I(3 downto 2);
                                sd_done               <= not sd_done;
                                sd_dout               <= wb_dat_i(31 downto 16);
                            end if;
                    

                        -- CAS2/3 ... are to handle burst transfers according to programmed Mode register word.
                        when CYCLE_CAS2 =>
                            if (sd_burst = '1') then 
                                sd_mxadr              <= "0000" & WB_ADR_I(23) & WB_ADR_I(8 downto 3) & "10";  -- no auto precharge
                                if (sd_reading = '1') then 
                                    sd_cmd            <= CMD_READ;
                                end if; 
                            end if;
    
                        when CYCLE_CAS3 =>
                            if (sd_burst = '1') then 
                                sd_mxadr              <= "0000" & WB_ADR_I(23) & WB_ADR_I(8 downto 3) & "11";  -- no auto precharge
                                if (sd_reading = '1') then 
                                    sd_cmd            <= CMD_READ;
                                end if; 
                            end if;
    
                        -- Data is available CAS Latency clocks after the read request, so these read operations operate in parallel to the CAS
                        -- cycles requesting the data. ie. CL=2 then CYCLE_READ0 will be processed same time as CYCLE_CAS2.
                        when CYCLE_READ0 =>
                            if (sd_reading = '1') then 
                                sd_dat(15 downto 0)   <= sd_din;
                            else
                                if (sd_writing = '1') then
                                    sd_cycle          <= CYCLE_END;
                                end if;
                            end if;
    
                        when CYCLE_READ1 =>
                            if (sd_reading = '1') then 
                                sd_dat(31 downto 16)  <= sd_din;
                                sd_done               <= not sd_done;
                            end if;
    
                        when CYCLE_READ2 =>
                            if (sd_reading = '1') then 
                                sd_dat_nxt(15 downto 0)<= sd_din;
                            end if;
    
                        when CYCLE_READ3 =>
                            if (sd_reading = '1') then 
                                sd_dat_nxt(31 downto 16)<= sd_din;
                            end if;
    
                        when CYCLE_END =>
                            sd_burst                  <= '0';
                            sd_cyc                    <= '0';
                            sd_stb                    <= '0';

                        when others =>
                    end case;
                else
                    sd_cycle                          <= 0;
                    sd_burst                          <= '0';
                end if;
            end if;
        end if;
    end process;

    -- WishBone interface for sending received data and setting up the correct ACK signal for any read/write activity.
    process(SD_RST, WB_CLK, sd_rdy)
    begin
        if (SD_RST = '1') then
            sd_done_last                              <= '0';
            wb_ack                                    <= '0';
            wb_burst                                  <= '0';

        -- If the SDRAM isnt ready, we can only wait.
        elsif sd_rdy = '0' then

        elsif rising_edge(WB_CLK) then

            -- Note SDRAM activity via a previous/last signal.
            sd_done_last                              <= sd_done;

            -- If there has been a change in the SDRAM activity and it hasnt been acknowleged, send the ACK else cancel any previous ACK.
            if (sd_done xor sd_done_last) = '1' and wb_ack = '0' then
                wb_ack                                <= '1';
            else
                wb_ack                                <= '0';
            end if;

            -- If we are in an active Cycle and the Strobe is activated, assign any read data to the WB bus.
            if (WB_STB_I = '1' and WB_CYC_I = '1') then 
    
                -- If there has been a change in the SDRAM activity and it hasnt been acknowledged, send the current data held to the WB Bus.
                if ((sd_done xor sd_done_last) = '1' and wb_ack = '0') then 
                    wb_dat_o                          <= sd_dat;
                    wb_burst                          <= burst_mode;
                end if;
        
                -- If there has been an acknowledge due to sending of the first data word and we are in burst mode, then send the 2nd read value 
                -- whilst maintaining the ack.
                if (wb_ack = '1' and wb_burst = '1') then 
                    wb_ack                            <= '1';
                    wb_burst                          <= '0';
                    wb_dat_o                          <= sd_dat_nxt;
                end if;
            else 
                 wb_burst                             <= '0';
            end if;
        end if;
    end process;

    sd_req                                   <= WB_STB_I & WB_CYC_I & not wb_ack;
    sd_bank                                  <= to_integer(unsigned(WB_ADR_I(22 downto 21)));
    sd_row                                   <= WB_ADR_I(20 downto 9);

    burst_mode                               <= '1' when WB_CTI_I = "010"                              else '0';
    can_burst                                <= '1' when WB_ADR_I(2) = '0'                             else '0';
    sd_reading                               <= '1' when sd_stb = '1' and sd_cyc = '1' and sd_we = '0' else '0';
    sd_writing                               <= '1' when sd_stb = '1' and sd_cyc = '1' and sd_we = '1' else '0';

    -- drive control signals according to current command
    SD_CS_n                                  <= sd_cmd(3);
    SD_RAS_n                                 <= sd_cmd(2);
    SD_CAS_n                                 <= sd_cmd(1);
    SD_WE_n                                  <= sd_cmd(0);
    SD_CKE                                   <= '1';
    SD_DQM                                   <= sd_mxadr(12 downto 11);    
    SD_ADDR                                  <= sd_mxadr;

    WB_ACK_O                                 <= wb_ack;
    SD_READY                                 <= sd_rdy;

end Structure;
