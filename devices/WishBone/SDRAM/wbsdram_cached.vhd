---------------------------------------------------------------------------------------------------------
--
-- Name:            wbsdram_cached.vhd
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

entity WBSDRAM is
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

        -- WishBone interface.
        WB_CLK                      : in    std_logic;                                  -- Master clock at which the Wishbone interface operates.
        WB_RST_I                    : in    std_logic;                                  -- high active sync reset
        WB_DATA_I                   : in    std_logic_vector(WORD_32BIT_RANGE);         -- Data input from Master
        WB_DATA_O                   : out   std_logic_vector(WORD_32BIT_RANGE);         -- Data output to Master
        WB_ACK_O                    : out   std_logic;
        WB_ADR_I                    : in    std_logic_vector(log2ceil(SDRAM_ROWS * SDRAM_COLUMNS * SDRAM_BANKS) downto 0);
        WB_SEL_I                    : in    std_logic_vector(3 downto 0);
        WB_CTI_I                    : in    std_logic_vector(2 downto 0);               -- 000 Classic cycle, 001 Constant address burst cycle, 010 Incrementing burst cycle, 111 End-of-Burst
        WB_STB_I                    : in    std_logic;
        WB_CYC_I                    : in    std_logic;                                  -- cpu/chipset requests cycle
        WB_WE_I                     : in    std_logic;                                  -- cpu/chipset requests write   
        WB_TGC_I                    : in    std_logic_vector(06 downto 0);              -- cycle tag
        WB_HALT_O                   : out   std_logic;                                  -- throttle master
        WB_ERR_O                    : out   std_logic                                   -- abnormal cycle termination    
    );
end WBSDRAM;

architecture Structure of WBSDRAM is

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
    constant BURST_LENGTH           :       std_logic_vector(2 downto 0) := "111";
    constant MODE                   :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0) := std_logic_vector(to_unsigned(to_integer(unsigned("00" & WRITE_BURST_MODE & OP_MODE & CAS_LATENCY & BURST_TYPE & BURST_LENGTH)), SDRAM_ROW_BITS)); 

    -- FSM Cycle States governed in units of time, the state changes location according to the configurable parameters to ensure correct actuation at the correct time.
    --
    constant CYCLE_PRECHARGE        :       integer := 0;                                                                           -- ~0
    constant CYCLE_RAS_START        :       integer := clockTicks(SDRAM_tRP, SDRAM_CLK_FREQ);                                       -- ~3
    constant CYCLE_CAS_START        :       integer := CYCLE_RAS_START  + clockTicks(SDRAM_tRCD, SDRAM_CLK_FREQ);                   -- ~3 + tRCD
    constant CYCLE_WRITE_END        :       integer := CYCLE_CAS_START  + 1;                                                        -- ~4 + tRCD
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
    type BankCacheArray is array(natural range 0 to SDRAM_BANKS-1) of std_logic_vector(((SDRAM_ROW_BITS-1)+SDRAM_BANK_BITS) downto 0);

    -- SDRAM domain signals.
    signal sdBusy                   :       std_logic;
    signal sdCycle                  :       integer range 0 to 31;
    signal sdDone                   :       std_logic;
    shared variable sdCmd           :       std_logic_vector(4 downto 0);
    signal sdRefreshCount           :       unsigned(11 downto 0);
    signal sdAutoRefresh            :       std_logic;
    signal sdResetTimer             :       unsigned(WORD_8BIT_RANGE);
    signal sdInResetCounter         :       unsigned(WORD_8BIT_RANGE);
    signal sdIsReady                :       std_logic;
    signal sdActiveRow              :       BankArray;
    signal sdActiveBank             :       std_logic_vector(1 downto 0);
    signal sdWriteColumnAddr        :       unsigned(SDRAM_COLUMN_BITS-1 downto 0);                    -- Address at byte level as bit 0 is used as part of the fifo write enable.
    signal sdWriteCnt               :       integer range 0 to SDRAM_COLUMNS-1;

    -- CPU domain signals.
    signal cpuBusy                  :       std_logic;
    signal cpuDQM                   :       std_logic_vector(3 downto 0);
    signal cpuBank                  :       natural range 0 to SDRAM_BANKS-1;
    signal cpuRow                   :       std_logic_vector(SDRAM_ROW_BITS-1 downto 0);
    signal cpuCol                   :       std_logic_vector(SDRAM_COLUMN_BITS-1 downto 0);
    signal cpuDataOut               :       std_logic_vector(WORD_32BIT_RANGE);
    signal cpuDataIn                :       std_logic_vector(WORD_32BIT_RANGE);
    signal cpuDoneLast              :       std_logic;
    signal cpuIsWriting             :       std_logic;
    signal cpuLastEN                :       std_logic;
    signal cpuCachedBank            :       std_logic_vector(SDRAM_BANK_BITS-1 downto 0);
    signal cpuCachedRow             :       BankCacheArray;
    signal wbACK                    :       std_logic;

    -- Infer a BRAM array for 4 banks of 16bit words. 32bit is created by 2 arrays.
    type ramArray is array(natural range 0 to ((SDRAM_COLUMNS/2)*4)-1) of std_logic_vector(WORD_8BIT_RANGE);

    -- Declare the BRAM arrays for 32bit as a set of 4 x 8bit banks.
    shared variable fifoCache_3 : ramArray :=
    (
        others => X"00"
    );
    shared variable fifoCache_2 : ramArray :=
    (
        others => X"00"
    );
    shared variable fifoCache_1 : ramArray :=
    (
        others => X"00"
    );
    shared variable fifoCache_0 : ramArray :=
    (
        others => X"00"
    );

    -- Fifo control signals.
    signal fifoDataOutHi            :       std_logic_vector(WORD_16BIT_RANGE);
    signal fifoDataOutLo            :       std_logic_vector(WORD_16BIT_RANGE);
    signal fifoDataInHi             :       std_logic_vector(WORD_16BIT_RANGE);
    signal fifoDataInLo             :       std_logic_vector(WORD_16BIT_RANGE);
    signal fifoSdWREN_1             :       std_logic;
    signal fifoSdWREN_0             :       std_logic;
    signal fifoCPUWREN_3            :       std_logic;
    signal fifoCPUWREN_2            :       std_logic;
    signal fifoCPUWREN_1            :       std_logic;
    signal fifoCPUWREN_0            :       std_logic;
begin

    -- Main FSM for SDRAM control and refresh.
    process(ALL)
    begin

        if (SDRAM_RST = '1') then
            sdResetTimer                              <= (others => '0'); -- 0 upto 127
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
            fifoSdWREN_0                              <= '0';
            fifoSdWREN_1                              <= '0';
            sdWriteColumnAddr                         <= (others => '0');

        elsif rising_edge(SDRAM_CLK) then

            -- Write Enables are only 1 clock wide, clear on each cycle.
            fifoSdWREN_1                              <= '0';
            fifoSdWREN_0                              <= '0';

            -- Tri-state control, set the SDRAM databus to tri-state if we are not in write mode.
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

                elsif ((cpuBusy = '1' and sdCycle = 0) or sdCycle /= 0) then -- or (sdCycle = 0 and CS = '1')) then 
 
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
                                sdCmd                 := CMD_WRITE;
                                if SDRAM_DATAWIDTH = 32 then
                                    SDRAM_ADDR        <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 2) & '0' & '0')), SDRAM_ROW_BITS)); -- CAS address = Address accessing 32bit data with no auto precharge
                                    SDRAM_DQ          <= cpuDataIn;                                                  -- Assign corresponding data to the SDRAM databus.
                                    SDRAM_DQM         <= not cpuDQM(3 downto 0);
                                    sdDone            <= '1';
                                    sdCycle           <= CYCLE_END;

                                    -- A fake statement used to convince Quartus Prime to infer block ram for the fifo and not use registers.
                                    fifoDataInHi      <= fifoDataOutHi;
                                    fifoDataInLo      <= fifoDataOutLo;

                                elsif SDRAM_DATAWIDTH = 16 then
                                    SDRAM_ADDR        <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 1) & '0')), SDRAM_ROW_BITS)); -- CAS address = Address accessing first 16bit location within the 32bit external alignment with no auto precharge
                                    SDRAM_DQ          <= cpuDataIn((SDRAM_DATAWIDTH*2)-1 downto SDRAM_DATAWIDTH);    -- Assign corresponding data to the SDRAM databus.
                                    SDRAM_DQM         <= not cpuDQM(3 downto 2);

                                    -- A fake statement used to convince Quartus Prime to infer block ram for the fifo and not use registers.
                                    fifoDataInHi      <= fifoDataOutHi;
                                else
                                    report "SDRAM datawidth parameter invalid, should be 16 or 32!" severity error;
                                end if;

                            else
                                -- Setup for a read.
                                sdCmd                 := CMD_READ;
                                SDRAM_ADDR            <= (others => '0');
                                SDRAM_DQM             <= "00";                                                       -- For reads dont mask the data output.
                                sdWriteCnt            <= SDRAM_COLUMNS-1;
                                sdWriteColumnAddr     <= (others => '1');
                            end if;
    
                        -- For writes, this state writes out the second word of a 32bit word if we have a 16bit wide SDRAM chip.
                        --
                        when CYCLE_WRITE_END =>
                            -- When writing, setup for a write with preset mask with the correct word.
                            if (cpuIsWriting = '1') then 
                                SDRAM_ADDR            <= std_logic_vector(to_unsigned(to_integer(unsigned(cpuCol(SDRAM_COLUMN_BITS-1 downto 1) & '1')), SDRAM_ROW_BITS)); -- CAS address = Next address accessing second 16bit location within the 32bit external alignment with no auto precharge
                                sdCmd                 := CMD_WRITE;
                                SDRAM_DQM             <= not cpuDQM(1 downto 0);
                                SDRAM_DQ              <= cpuDataIn(SDRAM_DATAWIDTH-1 downto 0);
                                sdDone                <= '1';
                                sdCycle               <= CYCLE_END;

                                -- A fake statement used to convince Quartus Prime to infer block ram for the fifo and not use registers.
                                fifoDataInLo          <= fifoDataOutLo;
                            end if;

                        -- Data is available after CAS Latency (2 or 3) clocks after the read request.
                        -- The data is read as a full page burst, 1 clock per word.
                        when CYCLE_READ_START =>

                            if SDRAM_DATAWIDTH = 32 then
                                fifoSdWREN_1          <= '1';
                                fifoSdWREN_0          <= '1';
                                sdWriteCnt            <= sdWriteCnt - 2;
                                sdWriteColumnAddr     <= sdWriteColumnAddr + 2;
                                fifoDataInHi          <= SDRAM_DQ(WORD_UPPER_16BIT_RANGE);
                                fifoDataInLo          <= SDRAM_DQ(WORD_LOWER_16BIT_RANGE);

                                if sdWriteCnt > 1 then
                                    sdCycle           <= CYCLE_READ_START;
                                end if;

                            elsif SDRAM_DATAWIDTH = 16 then
                                if fifoSdWREN_1 = '0' then
                                    fifoSdWREN_1      <= '1';
                                    fifoDataInHi      <= SDRAM_DQ;
                                else
                                    fifoSdWREN_0      <= '1';
                                    fifoDataInLo      <= SDRAM_DQ;
                                end if;
                                sdWriteCnt            <= sdWriteCnt - 1;
                                sdWriteColumnAddr     <= sdWriteColumnAddr + 1;

                                if sdWriteCnt > 0 then
                                    sdCycle           <= CYCLE_READ_START;
                                end if;

                            else
                                report "SDRAM datawidth parameter invalid, should be 16 or 32!" severity error;
                            end if;

                        when CYCLE_READ_END =>
                            sdDone                    <= '1';
    
                        when CYCLE_END =>
                            sdCycle                   <= 0;
                            sdDone                    <= '0';

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
        variable bank                : std_logic_vector(1 downto 0);
        variable row                 : std_logic_vector(SDRAM_ROW_BITS-1 downto 0);
        variable writeThru           : std_logic;
    begin

        -- Setup the bank and row as variables to make code reading easier.
        bank                                          := WB_ADR_I(SDRAM_ADDR_BITS-1) & WB_ADR_I((SDRAM_COLUMN_BITS+SDRAM_BANK_BITS-1) downto (SDRAM_COLUMN_BITS+1));
        row                                           := WB_ADR_I(SDRAM_ADDR_BITS-2 downto (SDRAM_COLUMN_BITS+SDRAM_BANK_BITS));

        -- For write operations, if the cached page row for the current bank is the same as the row given by the cpu then we write to both the SDRAM and to the cache.
        if cpuCachedBank(to_integer(unsigned(bank))) = '1' and cpuCachedRow(to_integer(unsigned(bank))) = WB_ADR_I(SDRAM_ADDR_BITS-1) & WB_ADR_I((SDRAM_COLUMN_BITS+SDRAM_BANK_BITS-1) downto (SDRAM_COLUMN_BITS+1)) & row then
            writeThru                                 := '1';
        else
            writeThru                                 := '0';
        end if;

        -- Setup signals to initial state, critical they start at the right values.
        if (WB_RST_I = '1') then
            cpuDoneLast                               <= '0';
            cpuBusy                                   <= '0';
            cpuBank                                   <= 0;
            cpuRow                                    <= (others => '0');
            cpuCol                                    <= (others => '0');
            cpuDQM                                    <= (others => '1');
            cpuLastEN                                 <= '0';
            cpuCachedBank                             <= (others => '0');
            cpuCachedRow                              <= ( others => (others => '0') );
            cpuIsWriting                              <= '0';            
            fifoCPUWREN_3                             <= '0';
            fifoCPUWREN_2                             <= '0';
            fifoCPUWREN_1                             <= '0';
            fifoCPUWREN_0                             <= '0';
            wbACK                                     <= '0';

        -- Wait for the SDRAM to become ready by holding the CPU in a wait state.
        elsif sdIsReady = '0' then
            cpuBusy                                   <= '1';

        elsif rising_edge(WB_CLK) then

            -- CPU Cache writes are only 1 cycle wide, so clear any asserted write.
            fifoCPUWREN_3                             <= '0';
            fifoCPUWREN_2                             <= '0';
            fifoCPUWREN_1                             <= '0';
            fifoCPUWREN_0                             <= '0';

            if wbACK = '1' then
                wbACK                                 <= '0';
            end if;

            -- Detect a Wishbone cycle and commence an SDRAM access.
            if (WB_STB_I = '1' and WB_CYC_I = '1' and cpuBusy = '0' and wbACK = '0') then

                -- Organisation of the memory is as follows:
                --
                -- Bank:   [(SDRAM_ADDR_BITS-1) .. (SDRAM_ADDR_BITS-1)] & [((SDRAM_COLUMN_BITS+SDRAM_BANK_BITS-1) .. (SDRAM_COLUMN_BITS+1)]
                -- Row:    [(SDRAM_ADDR_BITS-2) .. (SDRAM_COLUMN_BITS+SDRAM_BANK_BITS)]
                -- Column: [(SDRAM_COLUMN_BITS downto 2)]
                -- The bank is split so that the Bank MSB splits the SDRAM in 2, upper and lower segment, this is because Stack normally resides in the top upper
                -- segment and code in the bottom lower segment. The remaining bank bits are split at the page level such that 2 or more pages residing in different
                -- banks are contiguous, hoping to gain a little performance benefit through having a wider spread for code caching and stack caching and write thru.
                --
                cpuBank                               <= to_integer(unsigned(bank));
                cpuRow                                <= row;
                cpuCol                                <= WB_ADR_I(SDRAM_COLUMN_BITS downto 2) & '0';
                cpuDQM                                <= WB_SEL_I;
                cpuDataIn                             <= WB_DATA_I;

                -- For write operations, we write direct to memory. If the data is in cache then a write-thru is performed to preserve the cached bank.
                if WB_WE_I = '1' then

                    -- If we are writing to a cached page, update the changed bytes in cache.
                    if writeThru = '1' then
                        if WB_SEL_I(0) then
                            fifoCPUWREN_0             <= '1';
                        end if;
                        if WB_SEL_I(1) then
                            fifoCPUWREN_1             <= '1';
                        end if;
                        if WB_SEL_I(2) then
                            fifoCPUWREN_2             <= '1';
                        end if;
                        if WB_SEL_I(3) then
                            fifoCPUWREN_3             <= '1';
                        end if;
                    end if;

                    -- Set the flags, cpuBusy indicates to the SDRAM FSM to perform an operation.
                    cpuIsWriting                      <= WB_WE_I;
                    cpuBusy                           <= '1';

                -- For reads, if the row is cached then we just fall through to perform a read operation from cache otherwise the
                -- SDRAM needs to be instructed to read a page into cache before reading.
                --
                elsif cpuCachedBank(to_integer(unsigned(bank))) = '0' or cpuCachedRow(to_integer(unsigned(bank))) /= WB_ADR_I(SDRAM_ADDR_BITS-1) & WB_ADR_I((SDRAM_COLUMN_BITS+SDRAM_BANK_BITS-1) downto (SDRAM_COLUMN_BITS+1)) & row then

                    cpuCachedBank(to_integer(unsigned(bank))) <= '1';
                    cpuCachedRow (to_integer(unsigned(bank))) <= WB_ADR_I(SDRAM_ADDR_BITS-1) & WB_ADR_I((SDRAM_COLUMN_BITS+SDRAM_BANK_BITS-1) downto (SDRAM_COLUMN_BITS+1)) & row;

                    -- Set the flags, cpuBusy indicates to the SDRAM FSM to perform an operation.
                    cpuBusy                           <= '1';

                else
                    wbACK                             <= '1';
                end if;
            end if;

            -- Note SDRAM activity via a previous/last signal.
            cpuDoneLast                               <= sdDone;

            -- A change in the Done signal then we end the SDRAM request and release the CPU.
            if cpuDoneLast = '1' and sdDone = '0' then
                cpuBusy                               <= '0';
                cpuIsWriting                          <= '0';
                wbACK                                 <= '1';
            end if;
        end if;
    end process;

    -- System bus control signals.
    SDRAM_READY                              <= sdIsReady;

    -- Wishbone bus control signals.
    WB_ACK_O                                 <= wbACK;
    
    --- Throttle not needed.
    WB_HALT_O                                <= '0';

    --- Error not yet implemented.
    WB_ERR_O                                 <= '0';

    -------------------------------------------------------------------------------------------------------------------------
    -- Inferred Dual Port RAM.
    --
    -- The dual port ram is used to buffer a full page within the SDRAM, one buffer for each bank. The addressing is such 
    -- that half of the banks appear in the lower segment of the address space and half in the top segment, the MSB of the
    -- SDRAM address is used for the split. This is to cater for stack where typically, on the ZPU, the stack would reside
    -- in the very top of memory working down and the applications would reside at the bottom of the memory working up.
    --
    -------------------------------------------------------------------------------------------------------------------------

    -- SDRAM Side of dual port RAM.
    -- For Read:  fifoDataOutHi     <= fifoCache_3(sdWriteColumnAddr)
    --            fifoDataOutLo     <= fifoCache_0(sdWriteColumnAddr)
    -- For Write: fifoCache_3 _1    <= fifoDataIn when sdWriteColumnAddr(0) = '0'
    --            fifoCache_2 _0    <= fifoDataIn when sdWriteColumnAddr(0) = '1'
    --            fifoSdWREN must be asserted ('1') for write operations.
    process(ALL)
        variable cacheAddr           : unsigned(SDRAM_COLUMN_BITS-2+SDRAM_BANK_BITS downto 0);
    begin
        -- Setup the address based on the index (sdWriteColumnAddr) and the bank (cpuBank) as the cache is linear for 4 banks.
        --
        cacheAddr := to_unsigned(cpuBank, SDRAM_BANK_BITS) & sdWriteColumnAddr(SDRAM_COLUMN_BITS-1 downto 1); 

        if rising_edge(SDRAM_CLK) then
            if fifoSdWREN_1 = '1' then
                fifoCache_3(to_integer(cacheAddr))                                               := fifoDataInHi(WORD_UPPER_16BIT_RANGE);
                fifoCache_2(to_integer(cacheAddr))                                               := fifoDataInHi(WORD_LOWER_16BIT_RANGE);
            else
                fifoDataOutHi(WORD_UPPER_16BIT_RANGE)                                            <= fifoCache_3(to_integer(cacheAddr));
                fifoDataOutHi(WORD_LOWER_16BIT_RANGE)                                            <= fifoCache_2(to_integer(cacheAddr));
            end if;

            if fifoSdWREN_0 = '1' then
                fifoCache_1(to_integer(cacheAddr))                                               := fifoDataInLo(WORD_UPPER_16BIT_RANGE);
                fifoCache_0(to_integer(cacheAddr))                                               := fifoDataInLo(WORD_LOWER_16BIT_RANGE);
            else
                fifoDataOutLo(WORD_UPPER_16BIT_RANGE)                                            <= fifoCache_1(to_integer(cacheAddr));
                fifoDataOutLo(WORD_LOWER_16BIT_RANGE)                                            <= fifoCache_0(to_integer(cacheAddr));
            end if;
        end if;
    end process;

    -- CPU Side of dual port RAM, byte addressable.
    -- For Read:  DATA_OUT          <= fifoCache(bank + ADDR(COLUMN_BITS .. 2))
    -- For Write: fifoCache(0..3)   <= cpuDataIn
    process(ALL)
        variable cacheAddr           : unsigned(SDRAM_COLUMN_BITS-2+SDRAM_BANK_BITS downto 0);
    begin
        -- Setup the address based on the column address bits, 32 bit aligned and the bank (cpuBank) as the cache is linear for 4 banks.
        --
        cacheAddr := to_unsigned(cpuBank, SDRAM_BANK_BITS) & unsigned(WB_ADR_I(SDRAM_COLUMN_BITS downto 2)); 

        if rising_edge(WB_CLK) then
            if fifoCPUWREN_3 = '1' then
                fifoCache_3(to_integer(cacheAddr)) := cpuDataIn(31 downto 24);
            else
                WB_DATA_O((SDRAM_DATAWIDTH*2)-1 downto ((SDRAM_DATAWIDTH*2)-(SDRAM_DATAWIDTH/2)))<= fifoCache_3(to_integer(unsigned(cacheAddr)));
            end if;

            if fifoCPUWREN_2 = '1' then
                fifoCache_2(to_integer(cacheAddr)) := cpuDataIn(23 downto 16);
            else
                WB_DATA_O(((SDRAM_DATAWIDTH*2)-(SDRAM_DATAWIDTH/2))-1 downto SDRAM_DATAWIDTH)    <= fifoCache_2(to_integer(unsigned(cacheAddr)));
            end if;

            if fifoCPUWREN_1 = '1' then
                fifoCache_1(to_integer(cacheAddr)) := cpuDataIn(15 downto 8);
            else
                WB_DATA_O(SDRAM_DATAWIDTH-1 downto SDRAM_DATAWIDTH/2)                            <= fifoCache_1(to_integer(unsigned(cacheAddr)));
            end if;

            if fifoCPUWREN_0 = '1' then
                fifoCache_0(to_integer(cacheAddr)) := cpuDataIn(7 downto 0);
            else
                WB_DATA_O((SDRAM_DATAWIDTH/2)-1 downto 0)                                        <= fifoCache_0(to_integer(unsigned(cacheAddr)));
            end if;
        end if;
    end process;
end Structure;
