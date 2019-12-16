---------------------------------------------------------------------------------------------------------
--
-- Name:            sdram.vhd
-- Created:         September 2019
-- Original Author: Stephen J. Leary 2013-2014 
-- VHDL Author:     Philip Smart
-- Description:     Original Wishbone module written by Stephen J. Leary 2013-2014 in Verilog for use
--                  with the MT48LC16M16 chip.
--                  It has been translated into VHDL and adapted for the system bus and undergoing
--                  extensive modifications to work with the ZPU EVO processor, specifically burst
--                  tuning to enhance L2 Cache Fill performance.
-- Credits:         
-- Copyright:       Copyright (c) 2013-2014, Stephen J. Leary, All rights reserved.
--                  VHDL translation, sysbus adaptation and enhancements (c) 2019 Philip Smart
--                  <philip.smart@net2net.org>
--
-- History:         September 2019  - Initial module translation to VHDL based on Stephen J. Leary's Verilog
--                                    source code.
--                  November 2019   - Adapted for the system bus for use when no Wishbone interface is
--                                    instantiated in the ZPU Evo.
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
        MAX_DATACACHE_BITS    : integer := 4;                                     -- Maximum size in addr bits of 32bit datacache for burst transactions.
        SDRAM_COLUMNS         : integer := 256;                                   -- Number of Columns in an SDRAM page (ie. 1 row).
        SDRAM_ROWS            : integer := 4096;                                  -- Number of Rows in the SDRAM.
        SDRAM_BANKS           : integer := 4                                      -- Number of banks in the SDRAM.
    );
    port (
        -- SDRAM Interface
        SDRAM_CLK             : in    std_logic;                                  -- sdram is accessed at 100MHz
        SDRAM_RST             : in    std_logic;                                  -- reset the sdram controller.
        SDRAM_CKE             : out   std_logic;                                  -- clock enable.
        SDRAM_DQ              : inout std_logic_vector(15 downto 0);              -- 16 bit bidirectional data bus
        SDRAM_ADDR            : out   std_logic_vector(log2ceil(SDRAM_ROWS) - 1 downto 0);  -- Multiplexed address bus
        SDRAM_DQM             : out   std_logic_vector(log2ceil(SDRAM_BANKS) - 1 downto 0); -- Number of byte masks dependent on number of banks.
        SDRAM_BA              : out   std_logic_vector(log2ceil(SDRAM_BANKS) - 1 downto 0); -- Number of banks in SDRAM
        SDRAM_CS_n            : out   std_logic;                                  -- Single chip select
        SDRAM_WE_n            : out   std_logic;                                  -- write enable
        SDRAM_RAS_n           : out   std_logic;                                  -- row address select
        SDRAM_CAS_n           : out   std_logic;                                  -- columns address select
        SDRAM_READY           : out   std_logic;                                  -- sd ready.

        -- CPU Interface
        CLK                   : in    std_logic;                                  -- System master clock
        RESET                 : in    std_logic;                                  -- high active sync reset
        ADDR                  : in    std_logic_vector(21 downto 0);
        DATA_IN               : in    std_logic_vector(31 downto 0);              -- write data
        DATA_OUT              : out   std_logic_vector(31 downto 0);              -- read data
        WRITE_BYTE            : in    std_logic;                                  -- write a single byte as specified in A1:A0
        WRITE_HWORD           : in    std_logic;                                  -- write a 16bit word as specified in A1
        CS                    : in    std_logic;                                  -- Chip Select.
        WREN                  : in    std_logic;                                  -- Write enable.
        RDEN                  : in    std_logic;                                  -- Read enable.
        BUSY                  : out   std_logic                                   -- Memory is busy, hold CPU.
    );
end SDRAM;

architecture Structure of SDRAM is

    -- Constants to define the structure of the SDRAM in bits for provisioning of signals.
    constant SDRAM_ROW_BITS   :       integer := log2ceil(SDRAM_ROWS);
    constant SDRAM_COLUMN_BITS:       integer := log2ceil(SDRAM_COLUMNS);
    constant SDRAM_ARRAY_BITS :       integer := log2ceil(SDRAM_ROWS * SDRAM_COLUMNS);
    constant SDRAM_BANK_BITS  :       integer := log2ceil(SDRAM_BANKS);
    constant SDRAM_ADDR_BITS  :       integer := log2ceil(SDRAM_ROWS * SDRAM_COLUMNS * SDRAM_BANKS);

    -- Constants for correct operation of the SDRAM, these values are taken from the datasheet of the target device.
    --
    constant tRCD             :       integer := 4;                               -- tRCD - RAS to CAS minimum period, ie. 20ns -> 2 cycles@100MHz
    constant tRP              :       integer := 4;                               -- tRP - Precharge delay, min time for a precharge command to complete, ie. 15ns -> 2 cycles@100MHz
    constant tRFC             :       integer := 70;                              -- tRFC - Auto-refresh minimum time to complete, ie. 66ns
    constant tREF             :       integer := 64;                              -- tREF - period of time a complete refresh of all rows is made within.
    constant RAM_CLK          :       integer := 50000000;                        -- SDRAM Clock in Hertz

    -- Command table for a standard SDRAM.
    --
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

    -- Load Mode Register setting for a standard SDRAM.
    --
    -- xx:10  = Reserved            :
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
    constant MODE             :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0) := std_logic_vector(to_unsigned(to_integer(unsigned("00" & WRITE_BURST_MODE & OP_MODE & CAS_LATENCY & BURST_TYPE & BURST_LENGTH)), SDRAM_ROW_BITS)); 

    -- FSM Cycle States governed in units of time, the state changes location according to the configurable parameters to ensure correct actuation at the correct time.
    --
    constant CYCLE_PRECHARGE  :       integer := 0;                                                          -- 0
    constant CYCLE_RAS_START  :       integer := tRP;                                                        -- 3
    constant CYCLE_RAS_NEXT   :       integer := CYCLE_RAS_START  + 1;                                       -- 4
    constant CYCLE_CAS0       :       integer := CYCLE_RAS_START  + tRCD;                                    -- 3 + tRCD
    constant CYCLE_CAS1       :       integer := CYCLE_CAS0       + 1;                                       -- 4 + tRCD
    constant CYCLE_READ0      :       integer := CYCLE_CAS0       + to_integer(unsigned(CAS_LATENCY)) + 1;   -- 3 + tRCD + CAS_LATENCY
    constant CYCLE_READ1      :       integer := CYCLE_READ0      + 1;                                       -- 4 + tRCD + CAS_LATENCY
    constant CYCLE_END        :       integer := CYCLE_READ1      + 4;                                       -- 9 + tRCD + CAS_LATENCY
    constant CYCLE_RFSH_START :       integer := CYCLE_RAS_START;                                            -- 3
    constant CYCLE_RFSH_END   :       integer := CYCLE_RFSH_START + ((tRFC/RAM_CLK) * 10000000) + 1;         -- 3 + tRFC in clock ticks.

    -- Period in clock cycles between SDRAM refresh cycles.
    constant REFRESH_PERIOD   :       integer := (RAM_CLK / (tREF * SDRAM_ROWS)) - CYCLE_END;    

    type BankArray is array(natural range 0 to 3) of std_logic_vector(SDRAM_ROW_BITS-1 downto 0);

    -- Cache for holding burst reads to allow for differing speeds of WishBone Master.
    type DataCacheArray is array(natural range 0 to ((2**(MAX_DATACACHE_BITS))-1)) of std_logic_vector(WORD_32BIT_RANGE);
    signal readCache          :       DataCacheArray;
    attribute ramstyle        :       string;
    attribute ramstyle of readCache : signal is "logic";
    signal cacheReadAddr      :       unsigned(MAX_DATACACHE_BITS-1 downto 0);
    signal cacheWriteAddr     :       unsigned(MAX_DATACACHE_BITS-1 downto 0);

    signal sbBusy             :       std_logic;
    signal sdCycle            :       integer range 0 to 31;
    signal sdDone             :       std_logic;
    signal sdCmd              :       std_logic_vector(3 downto 0);
    signal sdRefreshCount     :       unsigned(9 downto 0);
    signal sdAutoRefresh      :       std_logic;

    signal sdResetTimer       :       unsigned(7 downto 0);
    signal sdMuxAddr          :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0);              -- 12 bit multiplexed address bus
    signal sdDoneLast         :       std_logic;
    signal sdInResetCounter   :       unsigned(7 downto 0);
    signal sdIsWriting        :       std_logic;
    signal isReady            :       std_logic;
    signal sdDataOut          :       std_logic_vector(15 downto 0);
    signal sdDataIn           :       std_logic_vector(15 downto 0);
    signal sdActiveRow        :       BankArray;
    signal sdActiveBank       :       std_logic_vector(1 downto 0);
    signal sdBank             :       natural range 0 to 3;
    signal sdRow              :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0);
    signal sdCol              :       std_logic_vector(SDRAM_COLUMN_BITS-1 downto 0);
    signal sdDQM              :       std_logic_vector(1 downto 0);
    signal sdCKE              :       std_logic;

    signal cpuDQM             :       std_logic_vector(3 downto 0);

    signal dout               :       std_logic_vector(31 downto 0);
    signal cpuDataIn          :       std_logic_vector(31 downto 0);
begin

    -- Tri-state control of the SDRAM data bus.
    process(sdIsWriting, SDRAM_DQ, sdDataOut)
    begin
        if (sdIsWriting = '1') then
            SDRAM_DQ                                  <= sdDataOut; 
            sdDataIn                                  <= SDRAM_DQ;
        else
            SDRAM_DQ                                  <= (others => 'Z');
            sdDataIn                                  <= SDRAM_DQ;
        end if;
    end process;

    -- Main FSM for SDRAM control and refresh.
    process(SDRAM_CLK, SDRAM_RST)
    begin
        if (SDRAM_RST = '1') then
            sdResetTimer                              <= (others => '0'); -- 0 upto 127
            sdInResetCounter                          <= (others => '1'); -- 255 downto 0
            sdMuxAddr                                 <= (others => '0');
            sdAutoRefresh                             <= '0';
            sdRefreshCount                            <= (others => '0');
            sdActiveBank                              <= (others => '0');
            sdActiveRow                               <= ((others => '0'), (others => '0'), (others => '0'), (others => '0'));
            isReady                                   <= '0';
            sdCmd                                     <= CMD_AUTO_REFRESH;
            sdCKE                                     <= '1';
            sdDQM                                     <= (others => '1');
            sdCycle                                   <= 0;
            sdDone                                    <= '0';
            cacheWriteAddr                            <= (others => '0');

        elsif rising_edge(SDRAM_CLK) then

            -- If no specific command given the default is NOP.
            sdCmd                                     <= CMD_NOP;

            -- Initialisation on power up or reset. The SDRAM must be given at least 200uS to initialise and a fixed setup pattern applied.
            if (isReady = '0') then
                sdResetTimer                          <= sdResetTimer  + 1;
    
                -- 1uS timer.
                if (sdResetTimer = RAM_CLK/1000000) then 
                    sdResetTimer                      <= (others => '0'); 
                    sdInResetCounter                  <= sdInResetCounter - 1;        
                end if;
    
                -- Every 1uS check for the next init action.
                if (sdResetTimer = 0) then 

                    -- 200uS wait, no action as the SDRAM starts up.
                    -- ie. 255 downto 55
    
                    -- Precharge all banks
                    if(sdInResetCounter = 55) then
                        sdCmd                         <= CMD_PRECHARGE;
                        sdMuxAddr(10)                 <= '1';
                    end if;

                    -- 8 auto refresh commands as specified in datasheet. The RFS time is 60nS, so using a 1uS timer, issue one after
                    -- the other.
                    if(sdInResetCounter >= 40 and sdInResetCounter <= 48) then
                        sdCmd                         <= CMD_AUTO_REFRESH;
                    end if;
    
                    -- Load the Mode register with our parameters.
                    if(sdInResetCounter = 39) then
                        sdCmd                         <= CMD_LOAD_MODE;
                        sdMuxAddr                     <= MODE;
                    end if;

                    -- 8 auto refresh commands as specified in datasheet. The RFS time is 60nS, so using a 1uS timer, issue one after
                    -- the other.
                    if(sdInResetCounter >= 30 and sdInResetCounter <= 38) then
                        sdCmd                         <= CMD_AUTO_REFRESH;
                    end if;
    
                    -- SDRAM ready.
                    if(sdInResetCounter = 20) then
                        isReady                       <= '1';
                    end if;
                end if;
            else

                sdRefreshCount                        <= sdRefreshCount + 1;

                -- Auto refresh. On timeout it kicks in so that 8192 auto refreshes are 
                -- issued in a 64ms period. Other bus operations are stalled during this period.
                if (sdRefreshCount > REFRESH_PERIOD and sdCycle = 0) then 
                    sdAutoRefresh                     <= '1';
                    sdRefreshCount                    <= (others => '0');
                    sdCmd                             <= CMD_PRECHARGE;
                    sdMuxAddr(10)                     <= '1';
                    sdActiveBank                      <= (others => '0');
                    sdActiveRow                       <= ((others => '0'), (others => '0'), (others => '0'), (others => '0'));
    
                -- In auto refresh period.
                elsif (sdAutoRefresh = '1') then 
    
                    -- while the cycle is active count.
                    sdCycle                           <= sdCycle +  1;
                    case (sdCycle) is 
                        when CYCLE_RFSH_START =>
                            sdCmd                     <= CMD_AUTO_REFRESH;
    
                        when CYCLE_RFSH_END =>
                            -- reset the count.
                            sdAutoRefresh             <= '0';
                            sdCycle                   <= 0;

                        when others =>
                    end case;
    
                elsif ((sbBusy = '1' and sdCycle = 0) or sdCycle /= 0) then -- or (sdCycle = 0 and CS = '1')) then 

                    -- while the cycle is active count.
                    sdCycle                           <= sdCycle + 1;
                    case (sdCycle) is

                        when CYCLE_PRECHARGE =>
                            -- If the bank is not open then no need to precharge, move onto RAS.
                            if (sdActiveBank(sdBank) = '0') then
                                sdCycle               <= CYCLE_RAS_START;

                            -- If the requested row is already active, go to CAS for immediate access to this row.
                            elsif (sdActiveRow(sdBank) = sdRow) then
                                sdCycle               <= CYCLE_CAS0;

                            -- Otherwise we close out the open bank by issuing a PRECHARGE.
                            else 
                                sdCmd                 <= CMD_PRECHARGE;
                                sdMuxAddr(10)         <= '0';
                                SDRAM_BA              <= std_logic_vector(to_unsigned(sdBank, SDRAM_BA'length));
                                sdActiveBank(sdBank)  <= '0';                                                        -- Store flag to indicate which bank is being made active.
                            end if;
    
                        -- Open the requested row.
                        when CYCLE_RAS_START =>
                            sdCmd                     <= CMD_ACTIVE;
                            sdMuxAddr                 <= sdRow;                                                      -- Addr presented to SDRAM as row address.
                            SDRAM_BA                  <= std_logic_vector(to_unsigned(sdBank, SDRAM_BA'length));     -- Addr presented to SDRAM as bank select.
                            sdActiveRow(sdBank)       <= sdRow;                                                      -- Store number of row being made active
                            sdActiveBank(sdBank)      <= '1';                                                        -- Store flag to indicate which bank is being made active.
                     
                        when CYCLE_RAS_NEXT =>
                            sdDQM                     <= "11";                                                       -- Set DQ to tri--state.
    
                        -- this is the first CAS cycle
                        when CYCLE_CAS0 =>
                            -- Process on a 32bit boundary, as this is a 16bit chip we need 2 accesses for a 32bit alignment.
                            sdMuxAddr                 <= std_logic_vector(to_unsigned(to_integer(unsigned(sdCol(SDRAM_COLUMN_BITS-1 downto 1) & '0')), SDRAM_ROW_BITS)); -- CAS address = Address accessing first 16bit location within the 32bit external alignment with no auto precharge
                            SDRAM_BA                  <= std_logic_vector(to_unsigned(sdBank, SDRAM_BA'length));     -- Ensure bank is the correct one opened.
    
                            -- If writing, setup for a write with preset mask.
                            if (sdIsWriting = '1') then 
                                sdCmd                 <= CMD_WRITE;
                                sdDQM                 <= not cpuDQM(3 downto 2);
                                sdDataOut             <= cpuDataIn(31 downto 16);                                    -- Assign corresponding data to the SDRAM databus.
                            else
                                -- Setup for a read.
                                sdCmd                 <= CMD_READ;
                                sdDQM                 <= "00";                                                       -- For reads dont mask the data output.
                            end if;
    
                        when CYCLE_CAS1 =>
                            sdMuxAddr                 <= std_logic_vector(to_unsigned(to_integer(unsigned(sdCol(SDRAM_COLUMN_BITS-1 downto 1) & '1')), SDRAM_ROW_BITS)); -- CAS address = Next address accessing second 16bit location within the 32bit external alignment with no auto precharge
                            SDRAM_BA                  <= std_logic_vector(to_unsigned(sdBank, SDRAM_BA'length));     -- Ensure bank is the correct one opened.

                            -- If writing, setup for a write with preset mask.
                            if (sdIsWriting = '1') then 
                                sdCmd                 <= CMD_WRITE;
                                sdDQM                 <= not cpuDQM(1 downto 0);
                                sdDone                <= not sdDone;
                                sdDataOut             <= cpuDataIn(15 downto 0);
           sdCycle <= CYCLE_END;
                            else
                                -- Setup for a read, change to write if flag set.
                                sdCmd                 <= CMD_READ;
                                sdDQM                 <= "00";                                                       -- For reads dont mask the data output.
                            end if;

                        -- Data is available CAS Latency clocks after the read request.
                        when CYCLE_READ0 =>
                            -- If writing, then we are complete, exit else read the first word.
                            if (sdIsWriting = '1') then
                                sdCycle               <= CYCLE_END;
                            else
                                dout(31 downto 16)    <= sdDataIn;
                            end if;
    
                        when CYCLE_READ1 =>
                            -- If writing, then we are complete, exit else read the first word.
                            if (sdIsWriting = '1') then
                                sdCycle               <= CYCLE_END;
                            else
                                dout(15 downto 0)     <= sdDataIn;
                                sdDone                <= not sdDone;
                            end if;
    
                        when CYCLE_END =>

                        when others =>
                    end case;
                else
                    sdCycle                           <= 0;
                end if;
            end if;
        end if;
    end process;

    -- CPU/BUS side logic. When the CPU initiates a transaction, capture the signals and the captured values are used within the SDRAM domain. This is to prevent
    -- any changes CPU side or differing signal lengths due to CPU architecture or clock being propogated into the SDRAM domain. The CPU only needs to know
    -- when the transation is complete and data read.
    --
    process(RESET, CLK, CS, WRITE_BYTE, WRITE_HWORD, ADDR, WREN, RDEN, isReady)
    begin
        if (RESET = '1') then
            sdDoneLast                                <= '0';
            sbBusy                                    <= '0';
            sdBank                                    <= 0;
            sdRow                                     <= (others => '0');
            sdCol                                     <= (others => '0');
            cpuDQM                                    <= (others => '1');
            sdIsWriting                               <= '0';

        -- If the SDRAM isnt ready, we can only wait.
        elsif isReady = '0' then

        elsif rising_edge(CLK) then

            -- Detect a Chip Select state change signalling access.
            if CS = '1' and (WREN='1' or RDEN='1') then
                sbBusy                                <= '1';
                sdIsWriting                           <= WREN;
                sdBank                                <= to_integer(unsigned(ADDR(SDRAM_ADDR_BITS-1 downto SDRAM_ARRAY_BITS)));
                sdRow                                 <= std_logic_vector(to_unsigned(to_integer(unsigned(ADDR(SDRAM_ARRAY_BITS + 1 - SDRAM_BANK_BITS downto SDRAM_COLUMN_BITS))), SDRAM_ROW_BITS));
                sdCol                                 <= ADDR(SDRAM_COLUMN_BITS-1 downto 0);

                -- Preset the write selects according to the CPU signals. Let Quartus optimize as easier to read seeing all mask values.
                if(WRITE_BYTE = '1') then
                    case ADDR(1 downto 0) is
                        when "00" => cpuDQM           <= "1000";
                                     cpuDataIn        <= DATA_IN(7 downto 0) & X"000000";
                        when "01" => cpuDQM           <= "0100";
                                     cpuDataIn        <= X"00" & DATA_IN(7 downto 0) & X"0000";
                        when "10" => cpuDQM           <= "0010";
                                     cpuDataIn        <= X"0000" & DATA_IN(7 downto 0) & X"00";
                        when "11" => cpuDQM           <= "0001";
                                     cpuDataIn        <= X"000000" & DATA_IN(7 downto 0);
                        when others =>
                    end case;
                    
                elsif(WRITE_HWORD = '1') then

                    case ADDR(1) is
                        when '0' =>  cpuDQM           <= "1100";
                                     cpuDataIn        <= DATA_IN(15 downto 0) & X"0000";
                        when '1' =>  cpuDQM           <= "0011";
                                     cpuDataIn        <= X"0000" & DATA_IN(15 downto 0);
                    end case;

                else
                    -- Reads are always 32bit wide and if no part word signal is asserted, writes are 32bit.
                    cpuDataIn                         <= DATA_IN(31 downto 0);
                    cpuDQM                            <= "1111";
                end if;
            end if;

            -- Note SDRAM activity via a previous/last signal.
            sdDoneLast                                <= sdDone;

            -- If there has been a change in the SDRAM activity reset the signals as initiated transaction is complete.
            if (sdDone xor sdDoneLast) = '1' then
                sbBusy                                <= '0';
                sdIsWriting                           <= '0';
            end if;

        end if;
    end process;

    DATA_OUT <= dout;

    -- drive control signals according to current command
    SDRAM_CS_n                               <= sdCmd(3);
    SDRAM_RAS_n                              <= sdCmd(2);
    SDRAM_CAS_n                              <= sdCmd(1);
    SDRAM_WE_n                               <= sdCmd(0);
    SDRAM_CKE                                <= sdCKE;
    SDRAM_DQM                                <= sdDQM;
    SDRAM_ADDR                               <= sdMuxAddr;

    -- System bus control signals.
    BUSY                                     <= sbBusy;
    SDRAM_READY                              <= isReady;

end Structure;
