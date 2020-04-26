---------------------------------------------------------------------------------------------------------
--
-- Name:            sdram.vhd
-- Created:         September 2019
-- Author:          Philip Smart
-- Description:     A configurable cached sdram controller for use with the ZPU EVO Processor and SoC.
--                  The module is instantiated with the parameters to describe the underlying SDRAM chip
--                  and in theory should work with most 16/32 bit SDRAM chips if they adhere to the SDRAM
--                  standard.
-- Credits:         Stephen J. Leary 2013-2014 - Basic sdram cycle structure of this module was based on 
--                  the verilog MT48LC16M16 chip controller written by Stephen.
-- Copyright:       (c) 2019-2020 Philip Smart <philip.smart@net2net.org>
--
-- History:         September 2019  - Initial module translation to VHDL based on Stephen J. Leary's Verilog
--                                    source code.
--                  November 2019   - Adapted for the system bus for use when no Wishbone interface is
--                                    instantiated in the ZPU Evo.
--                  December 2019   - Extensive changes, metability stability, autorefresh to ACTIVE timing
--                                    and parameterisation.
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
        MAX_DATACACHE_BITS          :       integer := 4;                               -- Maximum size in addr bits of 32bit datacache for burst transactions.
        SDRAM_ROWS                  :       integer := 4096;                            -- Number of Rows in the SDRAM.
        SDRAM_COLUMNS               :       integer := 256;                             -- Number of Columns in an SDRAM page (ie. 1 row).
        SDRAM_BANKS                 :       integer := 4;                               -- Number of banks in the SDRAM.
        SDRAM_DATAWIDTH             :       integer := 16;                              -- Data width of SDRAM chip (16, 32).
        SDRAM_CLK_FREQ              :       integer := 100000000;                       -- Frequency of the SDRAM clock in Hertz.
        SDRAM_tRCD                  :       integer := 20;                              -- tRCD - RAS to CAS minimum period (in ns).
        SDRAM_tRP                   :       integer := 20;                              -- tRP  - Precharge delay, min time for a precharge command to complete (in ns).
        SDRAM_tRFC                  :       integer := 70;                              -- tRFC - Auto-refresh minimum time to complete (in ns), ie. 66ns
        SDRAM_tREF                  :       integer := 64                               -- tREF - period of time a complete refresh of all rows is made within (in ms).
    );
    port (
        -- SDRAM Interface
        SDRAM_CLK                   : in    std_logic;                                  -- SDRAM is accessed at given clock, frequency specified in RAM_CLK.
        SDRAM_RST                   : in    std_logic;                                  -- Reset the sdram controller.
        SDRAM_CKE                   : out   std_logic;                                  -- Clock enable.
        SDRAM_DQ                    : inout std_logic_vector(SDRAM_DATAWIDTH-1 downto 0); -- Bidirectional data bus
        SDRAM_ADDR                  : out   std_logic_vector(log2ceil(SDRAM_ROWS) - 1 downto 0);  -- Multiplexed address bus
        SDRAM_DQM                   : out   std_logic_vector(log2ceil(SDRAM_BANKS) - 1 downto 0); -- Number of byte masks dependent on number of banks.
        SDRAM_BA                    : out   std_logic_vector(log2ceil(SDRAM_BANKS) - 1 downto 0); -- Number of banks in SDRAM
        SDRAM_CS_n                  : out   std_logic;                                  -- Single chip select
        SDRAM_WE_n                  : out   std_logic;                                  -- Write enable
        SDRAM_RAS_n                 : out   std_logic;                                  -- Row address select
        SDRAM_CAS_n                 : out   std_logic;                                  -- Columns address select
        SDRAM_READY                 : out   std_logic;                                  -- SD ready.

        -- CPU Interface
        CLK                         : in    std_logic;                                  -- System master clock
        RESET                       : in    std_logic;                                  -- High active sync reset
        ADDR                        : in    std_logic_vector(log2ceil(SDRAM_ROWS * SDRAM_COLUMNS * SDRAM_BANKS) downto 0);
        DATA_IN                     : in    std_logic_vector(WORD_32BIT_RANGE);         -- Write data
        DATA_OUT                    : out   std_logic_vector(WORD_32BIT_RANGE);         -- Read data
        WRITE_BYTE                  : in    std_logic;                                  -- Write a single byte as specified in A1:A0
        WRITE_HWORD                 : in    std_logic;                                  -- Write a 16bit word as specified in A1
        CS                          : in    std_logic;                                  -- Chip Select.
        WREN                        : in    std_logic;                                  -- Write enable.
        RDEN                        : in    std_logic;                                  -- Read enable.
        BUSY                        : out   std_logic                                   -- Memory is busy, hold CPU.
    );
end SDRAM;

architecture Structure of SDRAM is

    -- Constants to define the structure of the SDRAM in bits for provisioning of signals.
    constant SDRAM_ROW_BITS         :       integer := log2ceil(SDRAM_ROWS);
    constant SDRAM_COLUMN_BITS      :       integer := log2ceil(SDRAM_COLUMNS);
    constant SDRAM_ARRAY_BITS       :       integer := log2ceil(SDRAM_ROWS * SDRAM_COLUMNS);
    constant SDRAM_BANK_BITS        :       integer := log2ceil(SDRAM_BANKS);
    constant SDRAM_ADDR_BITS        :       integer := log2ceil(SDRAM_ROWS * SDRAM_COLUMNS * SDRAM_BANKS * (SDRAM_DATAWIDTH/8));

    -- Command table for a standard SDRAM.
    --
    -- Name                         (Function)                                     CKE  CS#  RAS# CAS# WE# DQM ADDR      DQ
    -- COMMAND INHIBIT              (NOP)                                           H    H    X    X    X   X   X        X
    -- NO OPERATION                 (NOP)                                           H    L    H    H    H   X   X        X
    -- ACTIVE                       (select bank and activate row)                  H    L    L    H    H   X   Bank/row X
    -- READ                         (select bank and column, and start READ burst)  H    L    H    L    H   L/H Bank/col X
    -- WRITE                        (select bank and column, and start WRITE burst) H    L    H    L    L   L/H Bank/col Valid
    -- BURST TERMINATE                                                              H    L    H    H    L   X   X        Active
    -- PRECHARGE                    (Deactivate row in bank or banks)               H    L    L    H    L   X   Code     X
    -- AUTO REFRESH or SELF REFRESH (enter self refresh mode)                       H    L    L    L    H   X   X        X
    -- LOAD MODE REGISTER                                                           H    L    L    L    L   X   Op-code  X
    -- Write enable/output enable                                                   H    X    X    X    X   L   X        Active
    -- Write inhibit/output High-Z                                                  H    X    X    X    X   H   X        High-Z
    -- Self Refresh Entry                                                           L    L    L    L    H   X   X        X
    -- Self Refresh Exit            (Device is idle)                                H    H    X    X    X   X   X        X
    -- Self Refresh Exit            (Device is in Self Refresh state)               H    L    H    H    X   X   X        X
    -- Clock suspend mode Entry                                                     L    X    X    X    X   X   X        X
    -- Clock suspend mode Exit                                                      H    X    X    X    X   X   X        X
    -- Power down mode Entry        (Device is idle)                                L    H    X    X    X   X   X        X
    -- Power down mode Entry        (Device is Active)                              L    L    H    H    X   X   X        X
    -- Power down mode Exit         (Any state)                                     H    H    X    X    X   X   X        X
    -- Power down mode Exit         (Device is powered down)                        H    L    H    H    X   X   X        X

    constant CMD_INHIBIT            :       std_logic_vector(4 downto 0) := "11111";
    constant CMD_NOP                :       std_logic_vector(4 downto 0) := "10111";
    constant CMD_ACTIVE             :       std_logic_vector(4 downto 0) := "10011";
    constant CMD_READ               :       std_logic_vector(4 downto 0) := "10101";
    constant CMD_WRITE              :       std_logic_vector(4 downto 0) := "10100";
    constant CMD_BURST_TERMINATE    :       std_logic_vector(4 downto 0) := "10110";
    constant CMD_PRECHARGE          :       std_logic_vector(4 downto 0) := "10010";
    constant CMD_AUTO_REFRESH       :       std_logic_vector(4 downto 0) := "10001";
    constant CMD_LOAD_MODE          :       std_logic_vector(4 downto 0) := "10000";
    constant CMD_SELF_REFRESH_START :       std_logic_vector(4 downto 0) := "00001";
    constant CMD_SELF_REFRESH_END   :       std_logic_vector(4 downto 0) := "10110";
    constant CMD_CLOCK_SUSPEND      :       std_logic_vector(4 downto 0) := "00000";
    constant CMD_CLOCK_RESTORE      :       std_logic_vector(4 downto 0) := "10000";
    constant CMD_POWER_DOWN         :       std_logic_vector(4 downto 0) := "01000";
    constant CMD_POWER_RESTORE      :       std_logic_vector(4 downto 0) := "01100";

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
    constant WRITE_BURST_MODE       :       std_logic := '1';
    constant OP_MODE                :       std_logic_vector(1 downto 0) := "00";
    constant CAS_LATENCY            :       std_logic_vector(2 downto 0) := "011";
    constant BURST_TYPE             :       std_logic := '0';
    constant BURST_LENGTH           :       std_logic_vector(2 downto 0) := "000";
    constant MODE                   :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0) := std_logic_vector(to_unsigned(to_integer(unsigned("00" & WRITE_BURST_MODE & OP_MODE & CAS_LATENCY & BURST_TYPE & BURST_LENGTH)), SDRAM_ROW_BITS)); 

    -- FSM Cycle States governed in units of time, the state changes location according to the configurable parameters to ensure correct actuation at the correct time.
    --
    constant CYCLE_PRECHARGE        :       integer := 0;                                                                           -- ~0
    constant CYCLE_RAS_START        :       integer := clockTicks(SDRAM_tRP, SDRAM_CLK_FREQ);                                       -- ~3
    constant CYCLE_CAS_START        :       integer := CYCLE_RAS_START  + clockTicks(SDRAM_tRCD, SDRAM_CLK_FREQ);                   -- ~3 + tRCD
    constant CYCLE_CAS_END          :       integer := CYCLE_CAS_START  + 1;                                                        -- ~4 + tRCD
    constant CYCLE_READ_START       :       integer := CYCLE_CAS_START  + to_integer(unsigned(CAS_LATENCY)) + 1;                    -- ~3 + tRCD + CAS_LATENCY
    constant CYCLE_READ_END         :       integer := CYCLE_READ_START + 1;                                                        -- ~4 + tRCD + CAS_LATENCY
    constant CYCLE_END              :       integer := CYCLE_READ_END   + 1;                                                        -- ~9 + tRCD + CAS_LATENCY
    constant CYCLE_RFSH_START       :       integer := clockTicks(SDRAM_tRP, SDRAM_CLK_FREQ);                                       -- ~tRP
    constant CYCLE_RFSH_END         :       integer := CYCLE_RFSH_START + clockTicks(SDRAM_tRFC, SDRAM_CLK_FREQ) + clockTicks(SDRAM_tRP, SDRAM_CLK_FREQ) + 1; -- ~tRP (start) + tRFC (min autorefresh time) + tRP (end) in clock ticks.

    -- Period in clock cycles between SDRAM refresh cycles. This equates to tREF / SDRAM_ROWS to evenly divide the time, then subtract the length of the refresh period as this is
    -- the time it takes when a refresh starts until completion.
    constant REFRESH_PERIOD         :       integer := (((SDRAM_tREF * SDRAM_CLK_FREQ ) / SDRAM_ROWS) - (SDRAM_tRFC * 1000)) / 1000;

    -- Array of row addresses, one per bank, to indicate the row in use per bank.
    type BankArray is array(natural range 0 to SDRAM_BANKS-1) of std_logic_vector(SDRAM_ROW_BITS-1 downto 0);

    -- SDRAM domain signals.
    signal sdBusy                   :       std_logic;
    signal sdCycle                  :       integer range 0 to 31;
    signal sdDataOut                :       std_logic_vector(WORD_32BIT_RANGE);
    signal sdDone                   :       std_logic;
    shared variable sdCmd           :       std_logic_vector(4 downto 0);
    signal sdRefreshCount           :       unsigned(11 downto 0);
    signal sdAutoRefresh            :       std_logic;
    signal sdResetTimer             :       unsigned(WORD_8BIT_RANGE);
    signal sdInResetCounter         :       unsigned(WORD_8BIT_RANGE);
    signal sdIsReady                :       std_logic;
    signal sdActiveRow              :       BankArray;
    signal sdActiveBank             :       std_logic_vector(1 downto 0);

    -- CPU domain signals.
    signal cpuBusy                  :       std_logic;
    signal cpuDQM                   :       std_logic_vector(3 downto 0);
    signal cpuDoneLast              :       std_logic;
    signal cpuBank                  :       natural range 0 to SDRAM_BANKS-1;
    signal cpuRow                   :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0);
    signal cpuCol                   :       std_logic_vector(SDRAM_COLUMN_BITS-1 downto 0);
    signal cpuDataIn                :       std_logic_vector(WORD_32BIT_RANGE);
    signal cpuIsWriting             :       std_logic;
    signal cpuLastEN                :       std_logic;

begin

    -- Main FSM for SDRAM control and refresh.
    process(ALL)
    begin

        if (SDRAM_RST = '1') then
            sdResetTimer                              <= (others => '0'); -- 0 upto 255
            sdInResetCounter                          <= (others => '1'); -- 255 downto 0
            sdAutoRefresh                             <= '0';
            sdRefreshCount                            <= (others => '0');
            sdActiveBank                              <= (others => '0');
            sdActiveRow                               <= ((others => '0'), (others => '0'), (others => '0'), (others => '0'));
            sdIsReady                                 <= '0';
            sdCmd                                     := CMD_AUTO_REFRESH;
            SDRAM_DQM                                 <= (others => '1');
            sdCycle                                   <= 0;
            sdDone                                    <= '0';

        elsif rising_edge(SDRAM_CLK) then

            -- Tri-state control of the SDRAM databus, when reading, the output drivers are disabled.
            if (cpuIsWriting = '0') then
                SDRAM_DQ                              <= (others => 'Z');
            end if;

            -- If no specific command given the default is NOP.
            sdCmd                                     := CMD_NOP;

            -- Initialisation on power up or reset. The SDRAM must be given at least 200uS to initialise and a fixed setup pattern applied.
            if (sdIsReady = '0') then
                sdResetTimer                          <= sdResetTimer  + 1;
    
                -- 1uS timer.
                if (sdResetTimer = SDRAM_CLK_FREQ/1000000) then 
                    sdResetTimer                      <= (others => '0'); 
                    sdInResetCounter                  <= sdInResetCounter - 1;        
                end if;
    
                -- Every 1uS check for the next init action.
                if (sdResetTimer = 0) then 

                    -- 200uS wait, no action as the SDRAM starts up.
                    -- ie. 255 downto 55
    
                    -- Precharge all banks
                    if(sdInResetCounter = 55) then
                        sdCmd                         := CMD_PRECHARGE;
                        SDRAM_ADDR(10)                <= '1';
                    end if;

                    -- 8 auto refresh commands as specified in datasheet. The RFS time is 60nS, so using a 1uS timer, issue one after
                    -- the other.
                    if(sdInResetCounter >= 40 and sdInResetCounter <= 48) then
                        sdCmd                         := CMD_AUTO_REFRESH;
                    end if;
    
                    -- Load the Mode register with our parameters.
                    if(sdInResetCounter = 39) then
                        sdCmd                         := CMD_LOAD_MODE;
                        SDRAM_ADDR                    <= MODE;
                    end if;

                    -- 8 auto refresh commands as specified in datasheet. The RFS time is 60nS, so using a 1uS timer, issue one after
                    -- the other.
                    if(sdInResetCounter >= 30 and sdInResetCounter <= 38) then
                        sdCmd                         := CMD_AUTO_REFRESH;
                    end if;
    
                    -- SDRAM ready.
                    if(sdInResetCounter = 20) then
                        sdIsReady                     <= '1';
                    end if;
                end if;

            else

                -- Counter to time periods between autorefresh.
                sdRefreshCount                        <= sdRefreshCount + 1;

                -- This mechanism is used to reduce the possibility of metastability issues due to differing clocks.
                -- We only act after both Busy signals are high, thus one SDRAM clock after cpuBusy goes high.
                sdBusy                                <= cpuBusy;

                -- If the SDRAM has completed its request, reset the done indicator as it is only 1 cycle wide.
 --               if sdDone = '1' then
 --                   sdDone                            <= '0';
 --               end if;

                -- Auto refresh. On timeout it kicks in so that ROWS auto refreshes are 
                -- issued in a tRFC period. Other bus operations are stalled during this period.
                if (sdRefreshCount > REFRESH_PERIOD and sdCycle = 0) then 
                    sdAutoRefresh                     <= '1';
                    sdRefreshCount                    <= (others => '0');
                    sdCmd                             := CMD_PRECHARGE;
                    SDRAM_ADDR(10)                    <= '1';
                    sdActiveBank                      <= (others => '0');
                    sdActiveRow                       <= ((others => '0'), (others => '0'), (others => '0'), (others => '0'));
    
                -- In auto refresh period.
                elsif (sdAutoRefresh = '1') then 
    
                    -- while the cycle is active count.
                    sdCycle                           <= sdCycle +  1;
                    case (sdCycle) is 
                        when CYCLE_RFSH_START =>
                            sdCmd                     := CMD_AUTO_REFRESH;
    
                        when CYCLE_RFSH_END =>
                            -- reset the count.
                            sdAutoRefresh             <= '0';
                            sdCycle                   <= 0;

                        when others =>
                    end case;

                elsif (((cpuBusy = '1' and sdBusy = '1') and sdCycle = 0) or sdCycle /= 0) then
 
                    -- while the cycle is active count.
                    sdCycle                           <= sdCycle + 1;
                    case (sdCycle) is

                        when CYCLE_PRECHARGE =>
                            -- If the bank is not open then no need to precharge, move onto RAS.
                            if (sdActiveBank(cpuBank) = '0') then
                                sdCycle               <= CYCLE_RAS_START;

                            -- If the requested row is already active, go to CAS for immediate access to this row.
                            elsif (sdActiveRow(cpuBank) = cpuRow) then
                                sdCycle               <= CYCLE_CAS_START;

                            -- Otherwise we close out the open bank by issuing a PRECHARGE.
                            else 
                                sdCmd                 := CMD_PRECHARGE;
                                SDRAM_ADDR(10)        <= '0';
                                SDRAM_BA              <= std_logic_vector(to_unsigned(cpuBank, SDRAM_BA'length));
                                sdActiveBank(cpuBank) <= '0';                                                        -- Store flag to indicate which bank is being made active.
                            end if;
    
                        -- Open the requested row.
                        when CYCLE_RAS_START =>
                            sdCmd                     := CMD_ACTIVE;
                            SDRAM_ADDR                <= cpuRow;                                                     -- Addr presented to SDRAM as row address.
                            SDRAM_BA                  <= std_logic_vector(to_unsigned(cpuBank, SDRAM_BA'length));    -- Addr presented to SDRAM as bank select.
                            sdActiveRow(cpuBank)      <= cpuRow;                                                     -- Store number of row being made active
                            sdActiveBank(cpuBank)     <= '1';                                                        -- Store flag to indicate which bank is being made active.
                     
                        -- CAS start, for 32 bit chips, only 1 CAS cycle is needed, for 16bit chips we need 2 to read/write 2x16bit words.
                        when CYCLE_CAS_START =>

                            -- If writing, setup for a write with preset mask.
                            if (cpuIsWriting = '1') then 

                                if SDRAM_DATAWIDTH = 32 then
                                    SDRAM_ADDR        <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 2) & '0' & '0')), SDRAM_ROW_BITS)); -- CAS address = Address accessing 32bit data with no auto precharge
                                    SDRAM_DQ          <= cpuDataIn;                                                  -- Assign corresponding data to the SDRAM databus.
                                    SDRAM_DQM         <= not cpuDQM(3 downto 0);
                                    sdCycle           <= CYCLE_END;
                                    sdDone            <= '1';

                                elsif SDRAM_DATAWIDTH = 16 then
                                    SDRAM_ADDR        <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 1) & '0')), SDRAM_ROW_BITS)); -- CAS address = Address accessing first 16bit location within the 32bit external alignment with no auto precharge
                                    SDRAM_DQ          <= cpuDataIn((SDRAM_DATAWIDTH*2)-1 downto SDRAM_DATAWIDTH);    -- Assign corresponding data to the SDRAM databus.
                                    SDRAM_DQM         <= not cpuDQM(3 downto 2);
                                else
                                    report "SDRAM datawidth parameter invalid, should be 16 or 32!" severity error;
                                end if;
                                sdCmd                 := CMD_WRITE;

                            else
                                -- Setup for a read.
                                sdCmd                 := CMD_READ;
                                SDRAM_ADDR            <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 1) & '0')), SDRAM_ROW_BITS)); -- CAS address = Address accessing first 16bit location within the 32bit external alignment with no auto precharge
                                SDRAM_DQM             <= "00";                                                       -- For reads dont mask the data output.
                            end if;
    
                        when CYCLE_CAS_END =>
                            SDRAM_ADDR                <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 1) & '1')), SDRAM_ROW_BITS)); -- CAS address = Next address accessing second 16bit location within the 32bit external alignment with no auto precharge

                            -- When writing, setup for a write with preset mask with the correct word.
                            if (cpuIsWriting = '1') then 
                                SDRAM_DQM             <= not cpuDQM(1 downto 0);
                                SDRAM_DQ              <= cpuDataIn(SDRAM_DATAWIDTH-1 downto 0);
                                sdDone                <= '1';
                                sdCycle               <= CYCLE_END;
                                sdCmd                 := CMD_WRITE;
                            else
                                -- Setup for a read, change to write if flag set.
                                sdCmd                 := CMD_READ;
                                SDRAM_DQM             <= "00";                                                       -- For reads dont mask the data output.
                            end if;

                        -- Data is available CAS Latency clocks after the read request. For 32bit chips, only 1 cycle is needed, for 16bit we need 2 read cycles of
                        -- 16 bits each.
                        when CYCLE_READ_START =>

                            if SDRAM_DATAWIDTH = 32 then
                              --sdDataOut             <= SDRAM_DQ;
                                DATA_OUT              <= SDRAM_DQ;
                                sdCycle               <= CYCLE_END;
                                sdDone                <= '1';
                                
                            elsif SDRAM_DATAWIDTH = 16 then
                              --  sdDataOut((SDRAM_DATAWIDTH*2)-1 downto SDRAM_DATAWIDTH) <= SDRAM_DQ;
                                DATA_OUT((SDRAM_DATAWIDTH*2)-1 downto SDRAM_DATAWIDTH) <= SDRAM_DQ;
                            else
                                report "SDRAM datawidth parameter invalid, should be 16 or 32!" severity error;
                            end if;

                        -- Second and final read cycle for 16bit SDRAM chips to create a 32bit word.
                        when CYCLE_READ_END =>
                            --sdDataOut(SDRAM_DATAWIDTH-1 downto 0) <= SDRAM_DQ;
                            DATA_OUT(SDRAM_DATAWIDTH-1 downto 0) <= SDRAM_DQ;
                            sdDone                    <= '1';
    
                        when CYCLE_END =>
                            sdDone                    <= '0';
                            sdCycle                   <= 0;

                        -- Other states are wait states, waiting for the correct time slot for SDRAM access.
                        when others =>
                    end case;
                else
                    sdCycle                           <= 0;
                end if;
            end if;

            -- drive control signals according to current command
            SDRAM_CKE                                 <= sdCmd(4);
            SDRAM_CS_n                                <= sdCmd(3);
            SDRAM_RAS_n                               <= sdCmd(2);
            SDRAM_CAS_n                               <= sdCmd(1);
            SDRAM_WE_n                                <= sdCmd(0);
        end if;

    end process;


    -- CPU/BUS side logic. When the CPU initiates a transaction, capture the signals and the captured values are used within the SDRAM domain. This is to prevent
    -- any changes CPU side or differing signal lengths due to CPU architecture or clock being propogated into the SDRAM domain. The CPU only needs to know
    -- when the transation is complete and data read.
    --
    process(ALL)
    begin
        if (RESET = '1') then
            cpuDoneLast                               <= '0';
            cpuBusy                                   <= '0';
            cpuBank                                   <= 0;
            cpuRow                                    <= (others => '0');
            cpuCol                                    <= (others => '0');
            cpuDQM                                    <= (others => '1');
            cpuLastEN                                 <= '0';

        -- Wait for the SDRAM to become ready by holding the CPU in a wait state.
        elsif sdIsReady = '0' then
            cpuBusy                                   <= '1';

        elsif rising_edge(CLK) then

            -- Preserve current enable state to detect activation.
            cpuLastEN <= (RDEN or WREN) and CS;

            -- Detect a Chip Select state change signalling access.
            if cpuLastEN = '0' and ((RDEN = '1' or WREN = '1') and CS = '1') then
                cpuBusy                               <= '1';
                cpuIsWriting                          <= WREN;
                cpuBank                               <= to_integer(unsigned(ADDR(SDRAM_ADDR_BITS-1 downto SDRAM_ARRAY_BITS+1)));
                cpuRow                                <= std_logic_vector(to_unsigned(to_integer(unsigned(ADDR(SDRAM_ARRAY_BITS downto SDRAM_COLUMN_BITS+1))), SDRAM_ROW_BITS));
                cpuCol                                <= ADDR(SDRAM_COLUMN_BITS downto 2) & '0';

                -- Preset the write selects according to the CPU signals. Let Quartus optimize as easier to read seeing all mask values.
                if(WRITE_BYTE = '1') then
                    case ADDR(1 downto 0) is
                        when "00" => cpuDQM           <= "1000";
                                     cpuDataIn        <= DATA_IN(WORD_8BIT_RANGE) & X"000000";
                        when "01" => cpuDQM           <= "0100";
                                     cpuDataIn        <= X"00" & DATA_IN(WORD_8BIT_RANGE) & X"0000";
                        when "10" => cpuDQM           <= "0010";
                                     cpuDataIn        <= X"0000" & DATA_IN(WORD_8BIT_RANGE) & X"00";
                        when "11" => cpuDQM           <= "0001";
                                     cpuDataIn        <= X"000000" & DATA_IN(WORD_8BIT_RANGE);
                        when others =>
                    end case;
                    
                elsif(WRITE_HWORD = '1') then

                    case ADDR(1) is
                        when '0' =>  cpuDQM           <= "1100";
                                     cpuDataIn        <= DATA_IN(WORD_16BIT_RANGE) & X"0000";
                        when '1' =>  cpuDQM           <= "0011";
                                     cpuDataIn        <= X"0000" & DATA_IN(WORD_16BIT_RANGE);
                    end case;

                else
                    -- Reads are always 32bit wide and if no part word signal is asserted, writes are 32bit.
                    cpuDataIn                         <= DATA_IN(WORD_32BIT_RANGE);
                    cpuDQM                            <= "1111";
                end if;
            end if;

            -- Note SDRAM activity via a previous/last signal.
            cpuDoneLast                               <= sdDone;

            -- A change in the Done signal indicates the end of the SDRAM request so read the data (read request) and release the CPU.
     --       if (cpuDoneLast = '0' and  sdDone = '1') then
     --           DATA_OUT                              <= sdDataOut;
     --       end if;
            if (cpuDoneLast = '0' and  sdDone = '1') or CS = '0' or (RDEN = '0' and WREN = '0') then
          --      DATA_OUT                              <= sdDataOut;
                cpuBusy                               <= '0';
                cpuIsWriting                          <= '0';
            end if;

        end if;
    end process;

    -- System bus control signals.
    BUSY                                     <= '1' when (cpuLastEN = '0' and (RDEN = '1' or WREN = '1') and CS = '1') else cpuBusy;
    --BUSY                                     <= cpuBusy;
    SDRAM_READY                              <= sdIsReady;

end Structure;
