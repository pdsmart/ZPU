---------------------------------------------------------------------------------------------------------
--
-- Name:            zpu_soc.vhd
-- Created:         January 2019
-- Author(s):       Philip Smart
-- Description:     ZPU System On a Chip
--                  This module contains the System on a Chip definition for the ZPU.
--                  Itś purpose is to provide a functional eco-system around the ZPU to actually perform
--                  real tasks. As a basic, boot and stack RAM, UART I/O and Timers are needed to at least
--                  present a monitor via UART for interaction. Upon this can be added an SD card for
--                  disk storage using the Fat FileSystem, SPI etc. Also, as the Wishbone interface is
--                  used in the Evo CPU, any number of 3rd party device IP Cores can be added relatively
--                  easily.
--
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         January 2019 - Initial creation.
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
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use work.zpu_soc_pkg.all;
use work.zpu_pkg.all;

entity zpu_soc is
    generic (
        SYSCLK_FREQUENCY          : integer := SYSTEM_FREQUENCY                       -- System clock frequency
    );
    port (
        -- Global Control --
        SYSCLK                    : in    std_logic;                                  -- System clock, running at frequency indicated in SYSCLK_FREQUENCY
        MEMCLK                    : in    std_logic;                                  -- Memory clock, running at twice frequency indicated in SYSCLK_FREQUENCY
        RESET_IN                  : in    std_logic;

        -- UART 0 & 1
        UART_RX_0                 : in    std_logic;
        UART_TX_0                 : out   std_logic;
        UART_RX_1                 : in    std_logic;
        UART_TX_1                 : out   std_logic;

        -- SPI signals
        SPI_MISO                  : in    std_logic := '1';                           -- Allow the SPI interface not to be plumbed in.
        SPI_MOSI                  : out   std_logic;
        SPI_CLK                   : out   std_logic;
        SPI_CS                    : out   std_logic;

        -- SD Card (SPI) signals
        SDCARD_MISO               : in    std_logic_vector(SOC_SD_DEVICES-1 downto 0) := (others => '1');
        SDCARD_MOSI               : out   std_logic_vector(SOC_SD_DEVICES-1 downto 0);
        SDCARD_CLK                : out   std_logic_vector(SOC_SD_DEVICES-1 downto 0);
        SDCARD_CS                 : out   std_logic_vector(SOC_SD_DEVICES-1 downto 0);
        
        -- PS/2 signals
        PS2K_CLK_IN               : in    std_logic := '1';
        PS2K_DAT_IN               : in    std_logic := '1';
        PS2K_CLK_OUT              : out   std_logic;
        PS2K_DAT_OUT              : out   std_logic;
        PS2M_CLK_IN               : in    std_logic := '1';
        PS2M_DAT_IN               : in    std_logic := '1';
        PS2M_CLK_OUT              : out   std_logic;
        PS2M_DAT_OUT              : out   std_logic;

        -- I²C signals
        I2C_SCL_IO                : inout std_logic;
        I2C_SDA_IO                : inout std_logic;    

        -- IOCTL Bus
        IOCTL_DOWNLOAD            : out   std_logic;                                  -- Downloading to FPGA.
        IOCTL_UPLOAD              : out   std_logic;                                  -- Uploading from FPGA.
        IOCTL_CLK                 : out   std_logic;                                  -- I/O Clock.
        IOCTL_WR                  : out   std_logic;                                  -- Write Enable to FPGA.
        IOCTL_RD                  : out   std_logic;                                  -- Read Enable from FPGA.
        IOCTL_SENSE               : in    std_logic;                                  -- Sense to see if HPS accessing ioctl bus.
        IOCTL_SELECT              : out   std_logic;                                  -- Enable IOP control over ioctl bus.
        IOCTL_ADDR                : out   std_logic_vector(24 downto 0);              -- Address in FPGA to write into.
        IOCTL_DOUT                : out   std_logic_vector(31 downto 0);              -- Data to be written into FPGA.
        IOCTL_DIN                 : in    std_logic_vector(31 downto 0);              -- Data to be read into HPS.

        -- SDRAM signals
        SDRAM_CLK                 : out   std_logic;                                  -- sdram is accessed at 100MHz
        SDRAM_CKE                 : out   std_logic;                                  -- clock enable.
        SDRAM_DQ                  : inout std_logic_vector(15 downto 0);              -- 16 bit bidirectional data bus
        SDRAM_ADDR                : out   std_logic_vector(12 downto 0);              -- 13 bit multiplexed address bus
        SDRAM_DQM                 : out   std_logic_vector(1 downto 0);               -- two byte masks
        SDRAM_BA                  : out   std_logic_vector(1 downto 0);               -- two banks
        SDRAM_CS_n                : out   std_logic;                                  -- a single chip select
        SDRAM_WE_n                : out   std_logic;                                  -- write enable
        SDRAM_RAS_n               : out   std_logic;                                  -- row address select
        SDRAM_CAS_n               : out   std_logic;                                  -- columns address select
        SDRAM_READY               : out   std_logic                                   -- sd ready.
);
end entity;

architecture rtl of zpu_soc is

    -- FSM States for the SD card to interface with the controller.
    type SDStateType is
    (
        SD_STATE_IDLE,
        SD_STATE_RESET,
        SD_STATE_RESET_1,
        SD_STATE_WRITE,
        SD_STATE_WRITE_1,
        SD_STATE_WRITE_2,
        SD_STATE_READ,
        SD_STATE_READ_1,
        SD_STATE_READ_2
    );

    -- Reset processing.
    signal RESET_n                :       std_logic := '0';
    signal RESET_COUNTER          :       unsigned(15 downto 0) := X"FFFF";
    signal RESET_COUNTER_RX       :       unsigned(15 downto 0) := X"FFFF";

    -- Millisecond counter
    signal MICROSEC_DOWN_COUNTER  :       unsigned(23 downto 0);                       -- Allow for 16 seconds delay.
    signal MILLISEC_DOWN_COUNTER  :       unsigned(17 downto 0);                       -- Allow for 262 seconds delay.
    signal MILLISEC_UP_COUNTER    :       unsigned(31 downto 0);                       -- Up counter allowing for 49 days count in milliseconds.
    signal SECOND_DOWN_COUNTER    :       unsigned(11 downto 0);                       -- Allow for 1 hour in seconds delay.
    signal MICROSEC_DOWN_TICK     :       integer range 0 to 150;                      -- Independent tick register to ensure down counter is accurate.
    signal MILLISEC_DOWN_TICK     :       integer range 0 to 150*1000;                 -- Independent tick register to ensure down counter is accurate.
    signal SECOND_DOWN_TICK       :       integer range 0 to 150*1000000;              -- Independent tick register to ensure down counter is accurate.
    signal MILLISEC_UP_TICK       :       integer range 0 to 150*1000;                 -- Independent tick register to ensure up counter is accurate.
    signal MICROSEC_DOWN_INTR     :       std_logic;                                   -- Interrupt when counter reaches 0.
    signal MICROSEC_DOWN_INTR_EN  :       std_logic;                                   -- Interrupt enable for microsecond down counter.
    signal MILLISEC_DOWN_INTR     :       std_logic;                                   -- Interrupt when counter reaches 0.
    signal MILLISEC_DOWN_INTR_EN  :       std_logic;                                   -- Interrupt enable for millisecond down counter.
    signal SECOND_DOWN_INTR       :       std_logic;                                   -- Interrupt when counter reaches 0.
    signal SECOND_DOWN_INTR_EN    :       std_logic;                                   -- Interrupt enable for second down counter.
    signal RTC_MICROSEC_TICK      :       integer range 0 to 150;                      -- Allow for frequencies upto 150MHz.
    signal RTC_MICROSEC_COUNTER   :       integer range 0 to 1000;                     -- Real Time Clock counters.
    signal RTC_MILLISEC_COUNTER   :       integer range 0 to 1000;
    signal RTC_SECOND_COUNTER     :       integer range 0 to 60;
    signal RTC_MINUTE_COUNTER     :       integer range 0 to 60;
    signal RTC_HOUR_COUNTER       :       integer range 0 to 24;
    signal RTC_DAY_COUNTER        :       integer range 1 to 32;
    signal RTC_MONTH_COUNTER      :       integer range 1 to 13;
    signal RTC_YEAR_COUNTER       :       integer range 0 to 4095;
    signal RTC_TICK_HALT          :       std_logic;
    
    -- Timer register block signals
    signal TIMER_REG_REQ          :       std_logic;
    signal TIMER1_TICK            :       std_logic;
    
    -- SPI Clock counter
    signal SPI_TICK               :       unsigned(8 downto 0);
    signal SPICLK_IN              :       std_logic;
    signal SPI_FAST               :       std_logic;
    
    -- SPI signals
    signal HOST_TO_SPI            :       std_logic_vector(7 downto 0);
    signal SPI_TO_HOST            :       std_logic_vector(31 downto 0);
    signal SPI_WIDE               :       std_logic;
    signal SPI_TRIGGER            :       std_logic;
    signal SPI_BUSY               :       std_logic;
    signal SPI_ACTIVE             :       std_logic;

    -- SD Card signals
    type SDAddrArray is array(natural range 0 to SOC_SD_DEVICES-1) of std_logic_vector(WORD_32BIT_RANGE);
    type SDDataArray is array(natural range 0 to SOC_SD_DEVICES-1) of std_logic_vector(7 downto 0);
    type SDErrorArray is array(natural range 0 to SOC_SD_DEVICES-1) of std_logic_vector(15 downto 0);
    --
    signal SD_RESET               :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- active-high, synchronous  reset.
    signal SD_RD                  :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- active-high read block request.
    signal SD_WR                  :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- active-high write block request.
    signal SD_CONTINUE            :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- If true, inc address and continue R/W.
    signal SD_CARD_TYPE           :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- Type of card, 0 = SD, 1 = SDHC
    signal SD_ADDR                :       SDAddrArray;                                 -- Block address.
    signal SD_DATA_READ           :       SDDataArray;                                 -- Data read from block.
    signal SD_DATA_WRITE          :       std_logic_vector(7 downto 0);                -- Data byte to write to block.
    signal SD_DATA_VALID          :       std_logic;                                   -- Flag to indicate when data has been received (rx).
    signal SD_DATA_REQ            :       std_logic;                                   -- Flag to indicate when data is valid for tx.
    signal SD_CHANNEL             :       integer range 0 to SOC_SD_DEVICES-1;         -- Active channel in the state machine.
    signal SD_BUSY                :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- High when controller is busy performing some operation.
    signal SD_HNDSHK_IN           :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- High when host has data to give or has taken data.
    signal SD_HNDSHK_OUT          :       std_logic_vector(SOC_SD_DEVICES-1 downto 0); -- High when controller has taken data or has data to give.
    signal SD_ERROR               :       SDErrorArray;                                -- Card error occurred (1).
    signal SD_OVERRUN             :       std_logic;                                   -- Receive data overrun flag.
    signal SD_STATE               :       SDStateType;                                 -- State machine states.
    signal SD_RESET_TIMER         :       integer range 0 to 100;                      -- 100ns reset timer, allows for SYSFREQ = 10 .. 100MHz.

    -- UART signals
    signal UART0_WR               :       std_logic;
    signal UART0_ADDR             :       std_logic;
    signal UART0_DATA_OUT         :       std_logic_vector(31 downto 0);
    signal UART0_TX_INTR          :       std_logic;
    signal UART0_RX_INTR          :       std_logic;
    signal UART1_WR               :       std_logic;
    signal UART1_ADDR             :       std_logic;
    signal UART1_DATA_OUT         :       std_logic_vector(31 downto 0);
    signal UART1_TX_INTR          :       std_logic;
    signal UART1_RX_INTR          :       std_logic;
    signal UART1_TX               :       std_logic;
    signal UART2_TX               :       std_logic;
    
    -- PS2 signals
    signal PS2_INT                :       std_logic;
    
    -- PS2 Keyboard Signals.
    signal KBD_IDLE               :       std_logic;
    signal KBD_RECV               :       std_logic;
    signal KBD_RECV_REG           :       std_logic;
    signal KBD_SEND_BUSY          :       std_logic;
    signal KBD_SEND_TRIGGER       :       std_logic;
    signal KBD_SEND_DONE          :       std_logic;
    signal KBD_SEND_BYTE          :       std_logic_vector(7 downto 0);
    signal KBD_RECV_BYTE          :       std_logic_vector(10 downto 0);

    -- I²C Signals.
    signal SCL_PAD_IN             :       std_logic;                                   -- i2c clock line input
    signal SCL_PAD_OUT            :       std_logic;                                   -- i2c clock line output
    signal SCL_PAD_OE             :       std_logic;                                   -- i2c clock line output enable, active low
    signal SDA_PAD_IN             :       std_logic;                                   -- i2c data line input
    signal SDA_PAD_OUT            :       std_logic;                                   -- i2c data line output
    signal SDA_PAD_OE             :       std_logic;                                   -- i2c data line output enable, active low
    signal WB_DATA_READ_I2C       :       std_logic_vector(WORD_32BIT_RANGE);          -- i2c data as 32bit word for placing on WB bus.
    signal WB_I2C_ACK             :       std_logic;
    signal WB_I2C_HALT            :       std_logic;
    signal WB_I2C_ERR             :       std_logic;
    signal WB_I2C_CS              :       std_logic;
    signal WB_I2C_IRQ             :       std_logic;

    signal WB_SDRAM_ACK           :       std_logic;
    signal WB_SDRAM_STB           :       std_logic;
    signal WB_DATA_READ_SDRAM     :       std_logic_vector(WORD_32BIT_RANGE);
    
    -- ZPU signals
    signal MEM_BUSY               :       std_logic;
    signal IO_WAIT_SPI            :       std_logic;
    signal IO_WAIT_SD             :       std_logic;
    signal IO_WAIT_PS2            :       std_logic;
    signal IO_WAIT_INTR           :       std_logic;
    signal IO_WAIT_TIMER1         :       std_logic;
    signal IO_WAIT_IOCTL          :       std_logic;
    signal MEM_DATA_READ          :       std_logic_vector(WORD_32BIT_RANGE);
    signal MEM_DATA_WRITE         :       std_logic_vector(WORD_32BIT_RANGE);
    signal MEM_ADDR               :       std_logic_vector(ADDR_BIT_RANGE);
    signal MEM_WRITE_ENABLE       :       std_logic; 
    signal MEM_WRITE_BYTE_ENABLE  :       std_logic; 
    signal MEM_WRITE_HWORD_ENABLE :       std_logic; 
    signal MEM_READ_ENABLE        :       std_logic;
    signal MEM_DATA_READ_INSN     :       std_logic_vector(WORD_32BIT_RANGE);
    signal MEM_ADDR_INSN          :       std_logic_vector(ADDR_BIT_RANGE);
    signal MEM_READ_ENABLE_INSN   :       std_logic;
    signal IO_DATA_READ           :       std_logic_vector(WORD_32BIT_RANGE);
    signal IO_DATA_READ_SPI       :       std_logic_vector(WORD_32BIT_RANGE);
    signal IO_DATA_READ_SD        :       std_logic_vector(WORD_32BIT_RANGE);
    signal IO_DATA_READ_PS2       :       std_logic_vector(WORD_32BIT_RANGE);
    signal IO_DATA_READ_INTRCTL   :       std_logic_vector(WORD_32BIT_RANGE);
    signal IO_DATA_READ_SOCCFG    :       std_logic_vector(WORD_32BIT_RANGE);
    signal IO_DATA_READ_IOCTL     :       std_logic_vector(WORD_32BIT_RANGE);

    -- ZPU ROM/BRAM/RAM/Stack signals.
    signal MEM_A_WRITE_ENABLE     :       std_logic;
    signal MEM_A_ADDR             :       std_logic_vector(ADDR_32BIT_RANGE);
    signal MEM_A_WRITE            :       std_logic_vector(WORD_32BIT_RANGE);
    signal MEM_B_WRITE_ENABLE     :       std_logic;
    signal MEM_B_ADDR             :       std_logic_vector(ADDR_32BIT_RANGE);
    signal MEM_B_WRITE            :       std_logic_vector(WORD_32BIT_RANGE);
    signal MEM_A_READ             :       std_logic_vector(WORD_32BIT_RANGE);
    signal MEM_B_READ             :       std_logic_vector(WORD_32BIT_RANGE);

    -- Master Wishbone Memory/IO bus interface.
    signal WB_CLK_I               :       std_logic;
    signal WB_RST_I               :       std_logic;
    signal WB_ACK_I               :       std_logic;
    signal WB_DAT_I               :       std_logic_vector(WORD_32BIT_RANGE);
    signal WB_DAT_O               :       std_logic_vector(WORD_32BIT_RANGE);
    signal WB_ADR_O               :       std_logic_vector(ADDR_BIT_RANGE);
    signal WB_CYC_O               :       std_logic;
    signal WB_STB_O               :       std_logic;
    signal WB_CTI_O               :       std_logic_vector(2 downto 0);
    signal WB_WE_O                :       std_logic;
    signal WB_SEL_O               :       std_logic_vector(WORD_4BYTE_RANGE);
    signal WB_HALT_I              :       std_logic;
    signal WB_ERR_I               :       std_logic;
    signal WB_INTA_I              :       std_logic;
    
    -- Interrupt signals
    signal INT_TRIGGERS           :       std_logic_vector(INTR_MAX downto 0);
    signal INT_ENABLE             :       std_logic_vector(INTR_MAX downto 0);
    signal INT_STATUS             :       std_logic_vector(INTR_MAX downto 0);
    signal INT_REQ                :       std_logic;
    signal INT_TRIGGER            :       std_logic;
    signal INT_ACK                :       std_logic;
    signal INT_DONE               :       std_logic;
    
    -- ZPU ROM/BRAM/RAM
    signal BRAM_SELECT            :       std_logic;
    signal RAM_SELECT             :       std_logic;
    signal BRAM_WREN              :       std_logic;
    signal RAM_WREN               :       std_logic;
    signal BRAM_DATA_READ         :       std_logic_vector(WORD_32BIT_RANGE);
    signal RAM_DATA_READ          :       std_logic_vector(WORD_32BIT_RANGE);
--    signal BRAM_READ_STATE      :       integer range 0 to 2 := 0;
--    signal BRAM_WRITE_STATE     :       integer range 0 to 2 := 0;
    
    -- IOCTL
    signal IOCTL_RDINT            :       std_logic;
    signal IOCTL_WRINT            :       std_logic;
    signal IOCTL_DATA_OUT         :       std_logic_vector(31 downto 0);
    
    -- IO Chip selects
    signal IO_SELECT              :       std_logic;                                       -- IO Range 0x<msb=0>7FFFFxxx of devices connected to the ZPU system bus.
    signal WB_IO_SELECT           :       std_logic;                                       -- IO Range of the ZPU CPU 0x<msb=1>F00000 .. 0x<nsb=1>FFFFFF
    signal WB_IO_SOC_SELECT       :       std_logic;                                       -- IO Range used within the SoC for small devices, upto 256 locations per device. 0x<msb=1>1F000xx
    signal IO_UART_SELECT         :       std_logic;                                       -- Uart Range 0xFFFFFAxx
    signal IO_INTR_SELECT         :       std_logic;                                       -- Interrupt Range 0xFFFFFBxx
    signal IO_TIMER_SELECT        :       std_logic;                                       -- Timer Range 0xFFFFFCxx
    signal IO_SPI_SELECT          :       std_logic;                                       -- SPI Range 0xFFFFFDxx
    signal IO_PS2_SELECT          :       std_logic;                                       -- PS2 Range 0xFFFFFExx
    signal IOCTL_CS               :       std_logic;                                       -- 0x800-80F
    signal SD_CS                  :       std_logic;                                       -- 0x900-93F
    signal UART0_CS               :       std_logic;                                       -- 0xA00-C0F
    signal UART1_CS               :       std_logic;                                       -- 0xA10-A1F
    signal INTR0_CS               :       std_logic;                                       -- 0xB00-B0F
    signal TIMER0_CS              :       std_logic;                                       -- 0xC00-C0F Millisecond timer.
    signal TIMER1_CS              :       std_logic;                                       -- 0xC10-C1F
    signal SPI0_CS                :       std_logic;                                       -- 0xD00-D0F
    signal PS2_CS                 :       std_logic;                                       -- 0xE00-E0F
    signal SOCCFG_CS              :       std_logic;                                       -- 0xF00-F0F

    function to_std_logic(L: boolean) return std_logic is
    begin
        if L then
            return('1');
        else
            return('0');
        end if;
    end function to_std_logic;
begin

    --
    -- Instantiation
    --
    -- Main CPU
    ZPUFLEX: if ZPU_FLEX = 1 generate
        ZPU0 : zpu_core_flex
            generic map (
                IMPL_MULTIPLY        => true,
                IMPL_COMPARISON_SUB  => true,
                IMPL_EQBRANCH        => true,
                IMPL_STOREBH         => false,
                IMPL_LOADBH          => false,
                IMPL_CALL            => true,
                IMPL_SHIFT           => true,
                IMPL_XOR             => true,
                CACHE                => false,
        --      IMPL_EMULATION       => minimal,
        --      REMAP_STACK          => false  --true, -- We need to remap the Boot ROM / Stack RAM so we can access SDRAM
                CLK_FREQ             => SYSCLK_FREQUENCY,
                STACK_ADDR           => SOC_STACK_ADDR          -- Initial stack address on CPU start.
            )
            port map (
                clk                  => SYSCLK,
                reset                => not RESET_n,
                enable               => '1',
                in_mem_busy          => MEM_BUSY,
                mem_read             => MEM_DATA_READ,
                mem_write            => MEM_DATA_WRITE,
                out_mem_addr         => MEM_ADDR,
                out_mem_writeEnable  => MEM_WRITE_ENABLE,
                out_mem_hEnable      => MEM_WRITE_HWORD_ENABLE,
                out_mem_bEnable      => MEM_WRITE_BYTE_ENABLE,
                out_mem_readEnable   => MEM_READ_ENABLE,
                interrupt_request    => INT_TRIGGER,
                interrupt_ack        => INT_ACK,                -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
                interrupt_done       => INT_DONE,               -- Interrupt service routine completed/done.
                break                => open,
                debug_txd            => UART2_TX,               -- Debug serial output.
                -- 
                MEM_A_WRITE_ENABLE   => MEM_A_WRITE_ENABLE,
                MEM_A_ADDR           => MEM_A_ADDR,
                MEM_A_WRITE          => MEM_A_WRITE,
                MEM_B_WRITE_ENABLE   => MEM_B_WRITE_ENABLE,
                MEM_B_ADDR           => MEM_B_ADDR,
                MEM_B_WRITE          => MEM_B_WRITE,
                MEM_A_READ           => MEM_A_READ,
                MEM_B_READ           => MEM_B_READ
            );
    end generate;
    ZPUSMALL: if ZPU_SMALL = 1 generate
        ZPU0 : zpu_core_small
            generic map (
                CLK_FREQ             => SYSCLK_FREQUENCY,
                STACK_ADDR           => SOC_STACK_ADDR          -- Initial stack address on CPU start.
            )
            port map (
                clk                  => SYSCLK,
                areset               => not RESET_n,
                enable               => '1',
                in_mem_busy          => MEM_BUSY, 
                mem_read             => MEM_DATA_READ,
                mem_write            => MEM_DATA_WRITE,
                out_mem_addr         => MEM_ADDR,
                out_mem_writeEnable  => MEM_WRITE_ENABLE,
                out_mem_hEnable      => MEM_WRITE_HWORD_ENABLE,
                out_mem_bEnable      => MEM_WRITE_BYTE_ENABLE,
                out_mem_readEnable   => MEM_READ_ENABLE,
                mem_writeMask        => open,
                interrupt_request    => INT_TRIGGER,
                interrupt_ack        => INT_ACK,                -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
                interrupt_done       => INT_DONE,               -- Interrupt service routine completed/done.
                break                => open,
                debug_txd            => UART2_TX,               -- Debug serial output.
                MEM_A_WRITE_ENABLE   => MEM_A_WRITE_ENABLE,
                MEM_A_ADDR           => MEM_A_ADDR,
                MEM_A_WRITE          => MEM_A_WRITE,
                MEM_B_WRITE_ENABLE   => MEM_B_WRITE_ENABLE,
                MEM_B_ADDR           => MEM_B_ADDR,
                MEM_B_WRITE          => MEM_B_WRITE,
                MEM_A_READ           => MEM_A_READ,
                MEM_B_READ           => MEM_B_READ
            );
    end generate;
    ZPUMEDIUM: if ZPU_MEDIUM = 1 generate
        ZPU0 : zpu_core_medium
            generic map (
                CLK_FREQ             => SYSCLK_FREQUENCY,
                STACK_ADDR           => SOC_STACK_ADDR          -- Initial stack address on CPU start.
            )
            port map (
                clk                  => SYSCLK,
                areset               => not RESET_n,
                enable               => '1',
                in_mem_busy          => MEM_BUSY,
                mem_read             => MEM_DATA_READ,
                mem_write            => MEM_DATA_WRITE,
                out_mem_addr         => MEM_ADDR,
                out_mem_writeEnable  => MEM_WRITE_ENABLE,
                out_mem_hEnable      => MEM_WRITE_HWORD_ENABLE,
                out_mem_bEnable      => MEM_WRITE_BYTE_ENABLE,
                out_mem_readEnable   => MEM_READ_ENABLE,
                mem_writeMask        => open,
                interrupt_request    => INT_TRIGGER,
                interrupt_ack        => INT_ACK,                -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
                interrupt_done       => INT_DONE,               -- Interrupt service routine completed/done.
                break                => open,
                debug_txd            => UART2_TX                -- Debug serial output.
            );
    end generate;
    ZPUEVO: if ZPU_EVO = 1 generate
        ZPU0 : zpu_core_evo
            generic map (
                -- Optional hardware features to be implemented.
                IMPL_HW_BYTE_WRITE   => EVO_USE_HW_BYTE_WRITE,  -- Enable use of hardware direct byte write rather than read 33bits-modify 8 bits-write 32bits.
                IMPL_HW_WORD_WRITE   => EVO_USE_HW_WORD_WRITE,  -- Enable use of hardware direct byte write rather than read 32bits-modify 16 bits-write 32bits.
                IMPL_OPTIMIZE_IM     => true,                   -- If the instruction cache is enabled, optimise Im instructions to gain speed.
                IMPL_USE_INSN_BUS    => SOC_IMPL_INSN_BRAM,     -- Use a seperate bus to read instruction memory, normally implemented in BRAM.
                IMPL_USE_WB_BUS      => EVO_USE_WB_BUS,         -- Use the wishbone interface in addition to direct access bus.    
                -- Optional instructions to be implemented in hardware:
                IMPL_ASHIFTLEFT      => true,                   -- Arithmetic Shift Left (uses same logic so normally combined with ASHIFTRIGHT and LSHIFTRIGHT).
                IMPL_ASHIFTRIGHT     => true,                   -- Arithmetic Shift Right.
                IMPL_CALL            => true,                   -- Call to direct address.
                IMPL_CALLPCREL       => true,                   -- Call to indirect address (add offset to program counter).
                IMPL_DIV             => true,                   -- 32bit signed division.
                IMPL_EQ              => true,                   -- Equality test.
                IMPL_EXTENDED_INSN   => true,                   -- Extended multibyte instruction set.
                IMPL_FIADD32         => false,                  -- Fixed point Q17.15 addition.
                IMPL_FIDIV32         => false,                  -- Fixed point Q17.15 division.
                IMPL_FIMULT32        => false,                  -- Fixed point Q17.15 multiplication.
                IMPL_LOADB           => true,                   -- Load single byte from memory.
                IMPL_LOADH           => true,                   -- Load half word (16bit) from memory.
                IMPL_LSHIFTRIGHT     => true,                   -- Logical shift right.
                IMPL_MOD             => true,                   -- 32bit modulo (remainder after division).
                IMPL_MULT            => true,                   -- 32bit signed multiplication.
                IMPL_NEG             => true,                   -- Negate value in TOS.
                IMPL_NEQ             => true,                   -- Not equal test.
                IMPL_POPPCREL        => true,                   -- Pop a value into the Program Counter from a location relative to the Stack Pointer.
                IMPL_PUSHSPADD       => true,                   -- Add a value to the Stack pointer and push it onto the stack.
                IMPL_STOREB          => true,                   -- Store/Write a single byte to memory/IO.
                IMPL_STOREH          => true,                   -- Store/Write a half word (16bit) to memory/IO.
                IMPL_SUB             => true,                   -- 32bit signed subtract.
                IMPL_XOR             => true,                   -- Exclusive or of value in TOS.
                -- Size/Control parameters for the optional hardware.
                MAX_INSNRAM_SIZE     => (2**(SOC_MAX_ADDR_INSN_BRAM_BIT)), -- Maximum size of the optional instruction BRAM on the INSN Bus.
                MAX_L1CACHE_BITS     => MAX_EVO_L1CACHE_BITS,   -- Maximum size in instructions of the Level 0 instruction cache governed by the number of bits, ie. 8 = 256 instruction cache.
                MAX_L2CACHE_BITS     => MAX_EVO_L2CACHE_BITS,   -- Maximum bit size in bytes of the Level 2 instruction cache governed by the number of bits, ie. 8 = 256 byte cache.
                MAX_MXCACHE_BITS     => MAX_EVO_MXCACHE_BITS,   -- Maximum size of the memory transaction cache governed by the number of bits.
                RESET_ADDR_CPU       => SOC_RESET_ADDR_CPU,     -- Initial start address of the CPU.
                START_ADDR_MEM       => SOC_START_ADDR_MEM,     -- Start address of program memory.
                STACK_ADDR           => SOC_STACK_ADDR,         -- Initial stack address on CPU start.
                CLK_FREQ             => SYSCLK_FREQUENCY        -- System clock frequency.
            )
            port map (
                CLK                  => SYSCLK,
                RESET                => not RESET_n,
                ENABLE               => '1',
                MEM_BUSY             => MEM_BUSY,
                MEM_DATA_IN          => MEM_DATA_READ,
                MEM_DATA_OUT         => MEM_DATA_WRITE,
                MEM_ADDR             => MEM_ADDR,
                MEM_WRITE_ENABLE     => MEM_WRITE_ENABLE,
                MEM_READ_ENABLE      => MEM_READ_ENABLE,
                MEM_WRITE_BYTE       => MEM_WRITE_BYTE_ENABLE,
                MEM_WRITE_HWORD      => MEM_WRITE_HWORD_ENABLE,
                -- Instruction memory path.
                MEM_BUSY_INSN        => '0',
                MEM_DATA_IN_INSN     => MEM_DATA_READ_INSN,
                MEM_ADDR_INSN        => MEM_ADDR_INSN,
                MEM_READ_ENABLE_INSN => MEM_READ_ENABLE_INSN,
                -- Master Wishbone Memory/IO bus interface.
                WB_CLK_I             => WB_CLK_I,
                WB_RST_I             => not RESET_n,
                WB_ACK_I             => WB_ACK_I,
                WB_DAT_I             => WB_DAT_I,
                WB_DAT_O             => WB_DAT_O,
                WB_ADR_O             => WB_ADR_O,
                WB_CYC_O             => WB_CYC_O,
                WB_STB_O             => WB_STB_O,
                WB_CTI_O             => WB_CTI_O,
                WB_WE_O              => WB_WE_O,
                WB_SEL_O             => WB_SEL_O,
                WB_HALT_I            => WB_HALT_I,
                WB_ERR_I             => WB_ERR_I,
                WB_INTA_I            => WB_INTA_I,
                --
                INT_REQ              => INT_TRIGGER,
                INT_ACK              => INT_ACK,                -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
                INT_DONE             => INT_DONE,               -- Interrupt service routine completed/done.
                BREAK                => open,                   -- A break instruction encountered.
                CONTINUE             => '1',                    -- When break activated, processing stops. Setting CONTINUE to logic 1 resumes processing with next instruction.
                DEBUG_TXD            => UART2_TX                -- Debug serial output.
            );
    end generate;
    ZPUEVOMIN: if ZPU_EVO_MINIMAL = 1 generate
        ZPU0 : zpu_core_evo
            generic map (
                -- Optional hardware features to be implemented.
                IMPL_HW_BYTE_WRITE   => EVO_USE_HW_BYTE_WRITE,  -- Enable use of hardware direct byte write rather than read 33bits-modify 8 bits-write 32bits.
                IMPL_HW_WORD_WRITE   => EVO_USE_HW_WORD_WRITE,  -- Enable use of hardware direct byte write rather than read 32bits-modify 16 bits-write 32bits.
                IMPL_OPTIMIZE_IM     => true,                   -- If the instruction cache is enabled, optimise Im instructions to gain speed.
                IMPL_USE_INSN_BUS    => SOC_IMPL_INSN_BRAM,    -- Use a seperate bus to read instruction memory, normally implemented in BRAM.
                IMPL_USE_WB_BUS      => EVO_USE_WB_BUS,         -- Use the wishbone interface in addition to direct access bus.    
                -- Optional instructions to be implemented in hardware:
                IMPL_ASHIFTLEFT      => false,                  -- Arithmetic Shift Left (uses same logic so normally combined with ASHIFTRIGHT and LSHIFTRIGHT).
                IMPL_ASHIFTRIGHT     => false,                  -- Arithmetic Shift Right.
                IMPL_CALL            => false,                  -- Call to direct address.
                IMPL_CALLPCREL       => false,                  -- Call to indirect address (add offset to program counter).
                IMPL_DIV             => false,                  -- 32bit signed division.
                IMPL_EQ              => false,                  -- Equality test.
                IMPL_EXTENDED_INSN   => false,                  -- Extended multibyte instruction set.
                IMPL_FIADD32         => false,                  -- Fixed point Q17.15 addition.
                IMPL_FIDIV32         => false,                  -- Fixed point Q17.15 division.
                IMPL_FIMULT32        => false,                  -- Fixed point Q17.15 multiplication.
                IMPL_LOADB           => false,                  -- Load single byte from memory.
                IMPL_LOADH           => false,                  -- Load half word (16bit) from memory.
                IMPL_LSHIFTRIGHT     => false,                  -- Logical shift right.
                IMPL_MOD             => false,                  -- 32bit modulo (remainder after division).
                IMPL_MULT            => false,                  -- 32bit signed multiplication.
                IMPL_NEG             => false,                  -- Negate value in TOS.
                IMPL_NEQ             => false,                  -- Not equal test.
                IMPL_POPPCREL        => false,                  -- Pop a value into the Program Counter from a location relative to the Stack Pointer.
                IMPL_PUSHSPADD       => false,                  -- Add a value to the Stack pointer and push it onto the stack.
                IMPL_STOREB          => false,                  -- Store/Write a single byte to memory/IO.
                IMPL_STOREH          => false,                  -- Store/Write a half word (16bit) to memory/IO.
                IMPL_SUB             => false,                  -- 32bit signed subtract.
                IMPL_XOR             => false,                  -- Exclusive or of value in TOS.
                -- Size/Control parameters for the optional hardware.
                MAX_INSNRAM_SIZE     => (2**(SOC_MAX_ADDR_INSN_BRAM_BIT)), -- Maximum size of the optional instruction BRAM on the INSN Bus.
                MAX_L1CACHE_BITS     => MAX_EVO_MIN_L1CACHE_BITS, -- Maximum size in instructions of the Level 0 instruction cache governed by the number of bits, ie. 8 = 256 instruction cache.
                MAX_L2CACHE_BITS     => MAX_EVO_MIN_L2CACHE_BITS, -- Maximum size in bytes of the Level 2 instruction cache governed by the number of bits, ie. 8 = 256 byte cache.
                MAX_MXCACHE_BITS     => MAX_EVO_MIN_MXCACHE_BITS, -- Maximum size of the memory transaction cache governed by the number of bits.
                RESET_ADDR_CPU       => SOC_RESET_ADDR_CPU,     -- Initial start address of the CPU.
                START_ADDR_MEM       => SOC_START_ADDR_MEM,     -- Start address of program memory.
                STACK_ADDR           => SOC_STACK_ADDR,         -- Initial stack address on CPU start.
                CLK_FREQ             => SYSCLK_FREQUENCY        -- System clock frequency.
            )
            port map (
                CLK                  => SYSCLK,
                RESET                => not RESET_n,
                ENABLE               => '1',
                MEM_BUSY             => MEM_BUSY,
                MEM_DATA_IN          => MEM_DATA_READ,
                MEM_DATA_OUT         => MEM_DATA_WRITE,
                MEM_ADDR             => MEM_ADDR,
                MEM_WRITE_ENABLE     => MEM_WRITE_ENABLE,
                MEM_READ_ENABLE      => MEM_READ_ENABLE,
                MEM_WRITE_BYTE       => MEM_WRITE_BYTE_ENABLE,
                MEM_WRITE_HWORD      => MEM_WRITE_HWORD_ENABLE,
                -- Instruction memory path.
                MEM_BUSY_INSN        => '0',
                MEM_DATA_IN_INSN     => MEM_DATA_READ_INSN,
                MEM_ADDR_INSN        => MEM_ADDR_INSN,
                MEM_READ_ENABLE_INSN => MEM_READ_ENABLE_INSN,
                -- Master Wishbone Memory/IO bus interface.
                WB_CLK_I             => WB_CLK_I,
                WB_RST_I             => not RESET_n,
                WB_ACK_I             => WB_ACK_I,
                WB_DAT_I             => WB_DAT_I,
                WB_DAT_O             => WB_DAT_O,
                WB_ADR_O             => WB_ADR_O,
                WB_CYC_O             => WB_CYC_O,
                WB_STB_O             => WB_STB_O,
                WB_CTI_O             => WB_CTI_O,
                WB_WE_O              => WB_WE_O,
                WB_SEL_O             => WB_SEL_O,
                WB_HALT_I            => WB_HALT_I,
                WB_ERR_I             => WB_ERR_I,
                WB_INTA_I            => WB_INTA_I,
                --
                INT_REQ              => INT_TRIGGER,
                INT_ACK              => INT_ACK,                -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
                INT_DONE             => INT_DONE,               -- Interrupt service routine completed/done.
                BREAK                => open,                   -- A break instruction encountered.
                CONTINUE             => '1',                    -- When break activated, processing stops. Setting CONTINUE to logic 1 resumes processing with next instruction.
                DEBUG_TXD            => UART2_TX                -- Debug serial output.
            );
    end generate;
    
    -- ROM
    ZPUROMFLEX : if (ZPU_FLEX = 1 or ZPU_SMALL = 1) and SOC_IMPL_BRAM = true generate
        ZPUROM : entity work.BootROM
            port map (
                clk                  => SYSCLK,
                memAWriteEnable      => MEM_A_WRITE_ENABLE,
                memAAddr             => MEM_A_ADDR(ADDR_BIT_BRAM_32BIT_RANGE),
                memAWrite            => MEM_A_WRITE,
                memBWriteEnable      => MEM_B_WRITE_ENABLE,
                memBAddr             => MEM_B_ADDR(ADDR_BIT_BRAM_32BIT_RANGE),
                memBWrite            => MEM_B_WRITE,
                memARead             => MEM_A_READ,
                memBRead             => MEM_B_READ
            );
    end generate;
    ZPUROMMEDIUM : if ZPU_MEDIUM = 1 and SOC_IMPL_BRAM = true generate
        ZPUROM : entity work.BootROM
            port map (
                clk                  => SYSCLK,
                memAWriteEnable      => BRAM_WREN,
                memAAddr             => MEM_ADDR(ADDR_BIT_BRAM_32BIT_RANGE),
                memAWrite            => MEM_DATA_WRITE,
                memBWriteEnable      => '0',
                memBAddr             => MEM_ADDR(ADDR_BIT_BRAM_32BIT_RANGE),
                memBWrite            => (others => '0'),
                memARead             => open,
                memBRead             => BRAM_DATA_READ
            );
    end generate;

    -- Evo system BRAM, dual port to allow for seperate instruction bus read.
    ZPUDPBRAMEVO : if (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and SOC_IMPL_INSN_BRAM = true and SOC_IMPL_BRAM = true generate
        ZPUBRAM : entity work.DualPortBootBRAM
            generic map (
                addrbits             => SOC_MAX_ADDR_BRAM_BIT
            )
            port map (
                clk                  => MEMCLK,
                memAAddr             => MEM_ADDR(ADDR_BIT_BRAM_RANGE),
                memAWriteEnable      => BRAM_WREN,
                memAWriteByte        => MEM_WRITE_BYTE_ENABLE,
                memAWriteHalfWord    => MEM_WRITE_HWORD_ENABLE,
                memAWrite            => MEM_DATA_WRITE,
                memARead             => BRAM_DATA_READ,

                memBAddr             => MEM_ADDR_INSN(ADDR_BIT_BRAM_32BIT_RANGE),
                memBWrite            => (others => '0'),
                memBWriteEnable      => '0',
                memBRead             => MEM_DATA_READ_INSN
            );
    end generate;
    -- Evo system BRAM, single port as no seperate instruction bus configured.
    ZPUBRAMEVO : if (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and SOC_IMPL_INSN_BRAM = false and SOC_IMPL_BRAM = true generate
        ZPUBRAM : entity work.SinglePortBootBRAM
            generic map (
                addrbits             => SOC_MAX_ADDR_BRAM_BIT
            )
            port map (
                clk                  => MEMCLK,
                memAAddr             => MEM_ADDR(ADDR_BIT_BRAM_RANGE),
                memAWriteEnable      => BRAM_WREN,
                memAWriteByte        => MEM_WRITE_BYTE_ENABLE,
                memAWriteHalfWord    => MEM_WRITE_HWORD_ENABLE,
                memAWrite            => MEM_DATA_WRITE,
                memARead             => BRAM_DATA_READ
            );
    end generate;

    -- Evo RAM, a block of RAM created as BRAM existing seperate to the main system BRAM, generally used for applications.
    ZPURAMEVO : if (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and SOC_IMPL_RAM = true generate
        ZPUBRAM : entity work.SinglePortBRAM
            generic map (
                addrbits             => SOC_MAX_ADDR_RAM_BIT
            )
            port map (
                clk                  => MEMCLK,
                memAAddr             => MEM_ADDR(ADDR_BIT_RAM_RANGE),
                memAWriteEnable      => RAM_WREN,
                memAWriteByte        => MEM_WRITE_BYTE_ENABLE,
                memAWriteHalfWord    => MEM_WRITE_HWORD_ENABLE,
                memAWrite            => MEM_DATA_WRITE,
                memARead             => RAM_DATA_READ
            );

            -- RAM Range SOC_ADDR_RAM_START) -> SOC_ADDR_RAM_END
            RAM_SELECT               <= '1' when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and (MEM_ADDR >= std_logic_vector(to_unsigned(SOC_ADDR_RAM_START, MEM_ADDR'LENGTH)) and MEM_ADDR < std_logic_vector(to_unsigned(SOC_ADDR_RAM_END, MEM_ADDR'LENGTH)))
                                        else '0';

            -- Enable write to RAM when selected and CPU in write state.
            RAM_WREN                 <= '1' when RAM_SELECT = '1' and MEM_WRITE_ENABLE = '1'
                                        else
                                        '0';
    end generate;

    -- Force the CPU to wait when slower memory/IO is accessed and it cant deliver an immediate result.
    MEM_BUSY                  <= '1'                  when (UART0_CS = '1' or UART1_CS = '1' or TIMER0_CS = '1') and MEM_READ_ENABLE = '1'
                                 else
                           --      '1' when BRAM_SELECT = '1'       and  (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and (MEM_READ_ENABLE = '1')
                           --      else
                           --      '1' when IO_SELECT = '1'         and  (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and (MEM_READ_ENABLE = '1')
                           --      else
                                 '1'                  when SOC_IMPL_SD = true      and IO_WAIT_SD = '1'
                                 else
                                 '1'                  when SOC_IMPL_SPI = true     and IO_WAIT_SPI = '1'
                                 else
                                 '1'                  when SOC_IMPL_PS2 = true     and IO_WAIT_PS2 = '1'
                                 else
                                 '1'                  when SOC_IMPL_INTRCTL = true and IO_WAIT_INTR = '1'
                                 else
                                 '1'                  when SOC_IMPL_TIMER1 = true  and IO_WAIT_TIMER1 = '1'
                                 else
                                 '1'                  when SOC_IMPL_IOCTL = true   and IO_WAIT_IOCTL = '1'
                                 else
                                 '1'                  when SOC_IMPL_SOCCFG = true  and SOCCFG_CS = '1' and MEM_READ_ENABLE = '1'
                                 else
                                 '0';

    -- Select CPU input source, memory or IO.
    MEM_DATA_READ             <= BRAM_DATA_READ       when BRAM_SELECT = '1'
                                 else
                                 RAM_DATA_READ        when SOC_IMPL_RAM = true     and RAM_SELECT = '1'
                                 else
                                 IO_DATA_READ_SD      when SOC_IMPL_SD = true      and SD_CS = '1'
                                 else
                                 IO_DATA_READ_SPI     when SOC_IMPL_SPI = true     and SPI0_CS = '1'
                                 else
                                 IO_DATA_READ_PS2     when SOC_IMPL_PS2 = true     and PS2_CS = '1'
                                 else
                                 IO_DATA_READ_INTRCTL when SOC_IMPL_INTRCTL = true and INTR0_CS = '1'
                                 else
                                 IO_DATA_READ_SOCCFG  when SOC_IMPL_SOCCFG = true  and SOCCFG_CS = '1'
                                 else
                                 IO_DATA_READ_IOCTL   when SOC_IMPL_IOCTL = true   and IOCTL_CS = '1'
                                 else
                                 IO_DATA_READ         when IO_SELECT = '1'
                                 else
                                 (others => '1');

    -- If the wishbone interface is implemented, generate the control and decode logic.
    WISHBONE_CTRL: if SOC_IMPL_WB = true generate
        WB_DAT_I              <= WB_DATA_READ_SDRAM   when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and SOC_IMPL_WB_SDRAM = true and WB_SDRAM_STB = '1'
                                 else
                                 X"000000" & WB_DATA_READ_I2C(BYTE_RANGE)  when SOC_IMPL_WB_I2C = true     and WB_I2C_CS = '1'
                                 else
                                 (others => '0');

        -- Acknowledge is a chain of all enabled device acknowledges as only the addressed device in any given occasion should generate an ACK.
        WB_ACK_I              <= WB_SDRAM_ACK         when SOC_IMPL_WB_SDRAM = true and WB_SDRAM_STB = '1'
                                 else
                                 WB_I2C_ACK           when SOC_IMPL_WB_I2C = true   and WB_I2C_CS = '1'
                                 -- access to an unimplemented area of memory, just ACK as there is nothing to handle the request.
                                 else '1';

        -- Halt/Wait signal is a chain of all enabled devices requiring additional bus transaction time.
        WB_HALT_I             <= WB_I2C_HALT          when SOC_IMPL_WB_I2C = true and WB_I2C_HALT = '1'
                                 else '0';

        -- Error signal is a chain of all enabled device error condition signals.
        WB_ERR_I              <= WB_I2C_ERR           when SOC_IMPL_WB_I2C = true and WB_I2C_ERR = '1'
                                 else '0';

        -- Interrupt signals are chained with the actual interrupt being stored in the main interrupt controller.
        WB_INTA_I             <= WB_I2C_IRQ           when SOC_IMPL_WB_I2C = true and WB_I2C_IRQ = '1'
                                 else '0';

        -- Like direct I/O, place peripherals in upper range of wishbone address space.
        WB_IO_SELECT          <= '1'                  when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and WB_STB_O = '1' and (WB_ADR_O >= std_logic_vector(to_unsigned(SOC_WB_IO_START, WB_ADR_O'LENGTH)) and WB_ADR_O < std_logic_vector(to_unsigned(SOC_WB_IO_END, WB_ADR_O'LENGTH)))
                                 else '0';

        WB_IO_SOC_SELECT      <= WB_IO_SELECT         when WB_ADR_O(19 downto 12) = X"00"
                                 else '0';

        WB_I2C_CS             <= '1'                  when WB_IO_SOC_SELECT = '1' and WB_ADR_O(11 downto 8) = "0000"                                            -- I2C Range 0x<msb=1>F000xx
                                 else '0';

        WB_CLK_I              <= SYSCLK;
    end generate;
    NO_WISHBONE: if SOC_IMPL_WB = false generate
        WB_DAT_I              <= (others => '0');
        WB_ACK_I              <= '0';
        WB_HALT_I             <= '0';
        WB_ERR_I              <= '0';
    end generate;

    -- Enable write to System BRAM when selected and CPU in write state.
    BRAM_WREN                 <= '1' when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and MEM_WRITE_ENABLE = '1' and (MEM_ADDR >= std_logic_vector(to_unsigned(SOC_ADDR_BRAM_START, MEM_ADDR'LENGTH)) and MEM_ADDR <= std_logic_vector(to_unsigned(SOC_ADDR_BRAM_END, MEM_ADDR'LENGTH)))
                                 else
                                 '1' when ZPU_MEDIUM = 1 and MEM_WRITE_ENABLE = '1' and MEM_ADDR(ioBit) = '0'
                                 else
                                 '0';

    -- Were not interested in the mouse, so pass through connection.
    PS2M_CLK_OUT              <= PS2M_CLK_IN;
    PS2M_DAT_OUT              <= PS2M_DAT_IN;

    -- Fixed peripheral Decoding.
                                 -- BRAM Range 0x00000000 - (2^SOC_MAX_ADDR_INSN_BRAM_BIT)-1
    BRAM_SELECT               <= '1'                  when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and (MEM_ADDR >= std_logic_vector(to_unsigned(SOC_ADDR_BRAM_START, MEM_ADDR'LENGTH)) and MEM_ADDR < std_logic_vector(to_unsigned(SOC_ADDR_BRAM_END, MEM_ADDR'LENGTH)))
                                 else
                                 '1'                  when (ZPU_MEDIUM = 1 or ZPU_FLEX = 1 or ZPU_SMALL = 1) and MEM_ADDR(ioBit) = '0'
                                 else '0';
                                 -- IO Range for EVO CPU
    IO_SELECT                 <= '1'                  when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and ((SOC_IMPL_WB = true and MEM_ADDR(WB_SELECT_BIT) = '0') or SOC_IMPL_WB = false) and MEM_ADDR(IO_DECODE_RANGE) = std_logic_vector(to_unsigned(255, maxAddrBit-1 - maxIOBit)) and MEM_ADDR(maxIOBit -1 downto 12) = std_logic_vector(to_unsigned(0, maxIOBit-12))
    --IO_SELECT                 <= '1' when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and MEM_ADDR(IO_DECODE_RANGE) = std_logic_vector(to_unsigned(255, maxAddrBit-1 - maxIOBit)) and MEM_ADDR(maxIOBit -1 downto 12) = std_logic_vector(to_unsigned(0, maxIOBit-12))
                                 else
                                 '1'                  when (ZPU_SMALL = 1 or ZPU_MEDIUM = 1 or ZPU_FLEX = 1) and MEM_ADDR(ioBit) = '1'                         -- IO Range for Small, Medium and Flex CPU
                                 else '0';
    IO_TIMER_SELECT           <= '1'                  when IO_SELECT = '1'         and MEM_ADDR(11 downto 8) = X"C"                                            -- Timer Range 0x<msb=0>FFFFCxx
                                 else '0';
    UART0_CS                  <= '1'                  when IO_SELECT = '1'         and MEM_ADDR(11 downto 4) = "10100000"                                      -- Uart Range 0x<msb=0>FFFFAxx, 0xA00-C0F
                                 else '0';
    UART1_CS                  <= '1'                  when IO_SELECT = '1'         and MEM_ADDR(11 downto 4) = "10100001"                                      -- Uart Range 0x<msb=0>FFFFAxx, 0xA10-A1F
                                 else '0';
    TIMER0_CS                 <= '1'                  when IO_TIMER_SELECT = '1'   and MEM_ADDR(7 downto 6) = "00"                                             -- 0xC00-C3F Millisecond timer.
                                 else '0';
    SD_CS                     <= '1'                  when IO_SELECT = '1'         and MEM_ADDR(11 downto 7) = "10010"                                         -- 0x900-90F 0x<msb=0>FFFF9xx, 0x900 - 0x90f First SD Card address range
                                 else '0';

    -- Mux the UART debug channel outputs. DBG1 is from the software controlled UART, DBG2 from the cpu channel.
    DEBUGUART: if DEBUG_CPU = true generate
        UART_TX_1             <= UART2_TX;
    end generate; 
    UART2: if DEBUG_CPU = false generate
        UART_TX_1             <= UART1_TX;
    end generate;

    ------------------------------------------------------------------------------------
    -- Direct Memory I/O devices
    ------------------------------------------------------------------------------------

    TIMER : if SOC_IMPL_TIMER1 = true generate
        -- TIMER
        TIMER1 : entity work.timer_controller
            generic map(
                prescale             => 1,                         -- Prescale incoming clock
                timers               => SOC_TIMER1_COUNTERS
            )
            port map (
                clk                  => SYSCLK,
                reset                => RESET_n,

                reg_addr_in          => MEM_ADDR(7 downto 0),
                reg_data_in          => MEM_DATA_WRITE,
                reg_rw               => '0', -- we never read from the timers
                reg_req              => TIMER_REG_REQ,

                ticks(0)             => TIMER1_TICK -- Tick signal is used to trigger an interrupt
            );

        process(SYSCLK, RESET_n)
        begin
            ------------------------
            -- HIGH LEVEL         --
            ------------------------

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
                TIMER_REG_REQ                                       <= '0';
                IO_WAIT_TIMER1                                      <= '0';

            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then

                IO_WAIT_TIMER1                                      <= '0';

                -- CPU Write?
                if MEM_WRITE_ENABLE = '1' and TIMER1_CS = '1' then

                    -- Write to Timer.
                    TIMER_REG_REQ                                   <= '1';

                -- IO Read?
                elsif MEM_READ_ENABLE = '1' and TIMER1_CS = '1' then

                end if;
            end if; -- rising-edge(SYSCLK)
        end process;

        TIMER1_CS                    <= '1' when IO_TIMER_SELECT = '1'  and MEM_ADDR(7 downto 6) = "01"     -- 0xC40-C7F
                                        else '0';
    end generate;

    -- PS2 devices
    PS2 : if SOC_IMPL_PS2 = true generate
        PS2KEYBOARD : entity work.io_ps2_com
            generic map (
                clockFilter          => 15,
                ticksPerUsec         => SYSCLK_FREQUENCY/(SYSCLK_FREQUENCY/100)
            )
            port map (
                clk                  => SYSCLK,
                reset                => not RESET_n,
                ps2_clk_in           => PS2K_CLK_IN,
                ps2_dat_in           => PS2K_DAT_IN,
                ps2_clk_out          => PS2K_CLK_OUT,
                ps2_dat_out          => PS2K_DAT_OUT,
                
                inIdle               => open,
                sendTrigger          => KBD_SEND_TRIGGER,
                sendByte             => KBD_SEND_BYTE,
                sendBusy             => KBD_SEND_BUSY,
                sendDone             => KBD_SEND_DONE,
                recvTrigger          => KBD_RECV,
                recvByte             => KBD_RECV_BYTE
            );

        process(SYSCLK, RESET_n)
        begin
            ------------------------
            -- HIGH LEVEL         --
            ------------------------

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
                KBD_SEND_TRIGGER                                    <= '0';
                KBD_RECV_REG                                        <= '0';
                IO_WAIT_PS2                                         <= '0';

            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then

                KBD_SEND_TRIGGER                                    <= '0';
                IO_WAIT_PS2                                         <= '0';

                -- CPU Write?
                if MEM_WRITE_ENABLE = '1' and PS2_CS = '1' then

                    -- Write to PS2 Controller.
                    KBD_SEND_BYTE                                   <= MEM_DATA_WRITE(7 downto 0);
                    KBD_SEND_TRIGGER                                <='1';

                -- IO Read?
                elsif MEM_READ_ENABLE = '1' and PS2_CS = '1' then

                    -- Read from PS2.
                    IO_DATA_READ_PS2                                <=(others  =>'0');
                    IO_DATA_READ_PS2(11 downto 0)                   <= KBD_RECV_REG & not KBD_SEND_BUSY & KBD_RECV_BYTE(10 downto 1);
                    KBD_RECV_REG                                    <='0';
                end if;

                -- PS2 interrupt
                PS2_INT                                             <= KBD_RECV or KBD_SEND_DONE;
                if KBD_RECV='1' then
                    KBD_RECV_REG                                    <= '1'; -- remains high until cleared by a read
                end if;

            end if; -- rising-edge(SYSCLK)
        end process;

        PS2_CS     <= '1' when IO_SELECT = '1'    and MEM_ADDR(11 downto 4) = "11010000"  -- PS2 Range 0xFFFFFExx, 0xE00-E0F
                      else '0';
    end generate;

    -- SPI host
    SPI : if SOC_IMPL_SPI = true generate

        SPI0 : entity work.spi_interface
            port map(
                sysclk               => SYSCLK,
                reset                => RESET_n,
        
                -- Host interface
                SPICLK_IN            => SPICLK_IN,
                HOST_TO_SPI          => HOST_TO_SPI,
                SPI_TO_HOST          => SPI_TO_HOST,
                trigger              => SPI_TRIGGER,
                busy                 => SPI_BUSY,
        
                -- Hardware interface
                miso                 => SPI_MISO,
                mosi                 => SPI_MOSI,
                spiclk_out           => SPI_CLK
            );

        -- SPI Timer
        process(SYSCLK)
        begin
            if rising_edge(SYSCLK) then
                SPICLK_IN                                           <= '0';
                SPI_TICK                                            <= SPI_TICK+1;
                if (SPI_FAST='1' and SPI_TICK(5)='1') or SPI_TICK(8)='1' then
                    SPICLK_IN                                       <= '1'; -- Momentary pulse for SPI host.
                    SPI_TICK                                        <= '0' & X"00";
                end if;
            end if;
        end process;

        process(SYSCLK, RESET_n)
        begin
            ------------------------
            -- HIGH LEVEL         --
            ------------------------

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
                SPI_CS                                              <= '1';
                SPI_ACTIVE                                          <= '0';
                IO_WAIT_SPI                                         <= '0';
    
            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then
    
                SPI_TRIGGER                                         <= '0';
                IO_WAIT_SPI                                         <= '0';
    
                -- CPU Write?
                if MEM_WRITE_ENABLE = '1' and SPI0_CS = '1' then
    
                    -- Write to the SPI.
                    case MEM_ADDR(3 downto 2) is
                        when "00"  => -- SPI CS
                            SPI_CS                                  <= not MEM_DATA_WRITE(0);
                            SPI_FAST                                <= MEM_DATA_WRITE(8);

                        when "01"  => -- SPI Data
                            SPI_WIDE                                <='0';
                            SPI_TRIGGER                             <= '1';
                            HOST_TO_SPI                             <= MEM_DATA_WRITE(7 downto 0);
                            SPI_ACTIVE                              <= '1';
                            IO_WAIT_SPI                             <= '1';
                        
                        when "10"  => -- SPI Pump (32-bit read)
                            SPI_WIDE                                <= '1';
                            SPI_TRIGGER                             <= '1';
                            HOST_TO_SPI                             <= MEM_DATA_WRITE(7 downto 0);
                            SPI_ACTIVE                              <= '1';
                            IO_WAIT_SPI                             <= '1';

                        when others =>
                    end case;
    
                -- IO Read?
                elsif MEM_READ_ENABLE = '1' and SPI0_CS = '1' then
    
                    -- Read from SPI.
                    case MEM_ADDR(3 downto 2) is
                        when "00"  => -- SPI CS
                            IO_DATA_READ_SPI                        <= (others =>'X');
                            IO_DATA_READ_SPI(15)                    <= SPI_BUSY;

                        when "01"  => -- SPI Data
                            SPI_ACTIVE                              <= '1';
                            IO_WAIT_SPI                             <= '1';
                        
                        when "10"  => -- SPI Pump (32-bit read)
                            SPI_WIDE                                <= '1';
                            SPI_TRIGGER                             <= '1';
                            SPI_ACTIVE                              <= '1';
                            HOST_TO_SPI                             <= X"FF";
                            IO_WAIT_SPI                             <= '1';

                        when others =>
                    end case;
                end if;
    
                -- SPI cycles
                if SPI_ACTIVE='1' then
                    IO_WAIT_SPI                                     <= SPI_BUSY;
                    if SPI_BUSY = '0' then
                        IO_DATA_READ_SPI                            <= SPI_TO_HOST;
                        SPI_ACTIVE                                  <= '0';
                    end if;
                end if;
            end if; -- rising-edge(SYSCLK)
        end process;

        SPI0_CS     <= '1' when IO_SELECT = '1'    and MEM_ADDR(11 downto 4) = "11010000"  -- SPI Range 0xFFFFFDxx, 0xD00-D0F
                       else '0';
    end generate;

    -- SD Card interface. Upto 4 SD Cards can be configured, add an entity for each and set the generics to the values required.
    -- The signals are in the form of an array, so device 0 uses signals in array element 0.
    SDCARD0: if SOC_IMPL_SD = true and SOC_SD_DEVICES >= 1 generate

        SDCARDS: for I in 0 to SOC_SD_DEVICES-1 generate
            SDCARD : entity work.SDCard
                generic map 
                (
                    FREQ_G               => (Real(SYSCLK_FREQUENCY / 1000000)), -- Master clock frequency (MHz).
                    INIT_SPI_FREQ_G      => 0.4,                          -- Slow SPI clock freq. during initialization (MHz).
                    SPI_FREQ_G           => 25.0,                         -- Operational SPI freq. to the SD card (MHz).
                    BLOCK_SIZE_G         => 512                           -- Number of bytes in an SD card block or sector.
                )
                port map
                (
                    -- Host-side interface signals.
                    clk_i                => SYSCLK,                       -- Master clock.
                    reset_i              => SD_RESET(I),                  -- active-high, synchronous  reset.
                    cardtype             => SD_CARD_TYPE(I),              -- 0 = SD, 1 = SDHC.
                    rd_i                 => SD_RD(I),                     -- active-high read block request.
                    wr_i                 => SD_WR(I),                     -- active-high write block request.
                    continue_i           => SD_CONTINUE(I),               -- If true, inc address and continue R/W.
                    addr_i               => SD_ADDR(I),                   -- Block address.
                    data_i               => SD_DATA_WRITE(7 downto 0),    -- Data to write to block.
                    data_o               => SD_DATA_READ(I)(7 downto 0),  -- Data read from block.
                    busy_o               => SD_BUSY(I),                   -- High when controller is busy performing some operation.
                    hndShk_i             => SD_HNDSHK_IN(I),              -- High when host has data to give or has taken data.
                    hndShk_o             => SD_HNDSHK_OUT(I),             -- High when controller has taken data or has data to give.
                    error_o              => SD_ERROR(I),                  -- Card error occurred (1).
                    -- I/O signals to the external SD card.
                    cs_bo                => SDCARD_CS(I),                 -- Active-low chip-select.
                    sclk_o               => SDCARD_CLK(I),                -- Serial clock to SD card.
                    mosi_o               => SDCARD_MOSI(I),               -- Serial data output to SD card.
                    miso_i               => SDCARD_MISO(I)                -- Serial data input from SD card.
                );
        end generate;
    end generate;
    --
    SDCARDCTL: if SOC_IMPL_SD = true and SOC_SD_DEVICES >= 1 generate

        process(SYSCLK, RESET_n, MEM_ADDR)
            variable tChannel                  : integer range 0 to SOC_SD_DEVICES-1;
        begin

            ------------------------
            -- HIGH LEVEL         --
            ------------------------
    
            -- Channel being accessed is in addr bits 5:4.
            tChannel                                                := to_integer(unsigned(MEM_ADDR(6 downto 4)));

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
                SD_ADDR                                             <= (others => (others => DontCareValue));
                SD_RD                                               <= (others => '0');
                SD_WR                                               <= (others => '0');
                SD_RESET                                            <= (others => '0');
                SD_CARD_TYPE                                        <= (others => '0');
                SD_CONTINUE                                         <= (others => '0');
                SD_HNDSHK_IN                                        <= (others => '0');
                SD_OVERRUN                                          <= '0'; 
                SD_DATA_REQ                                         <= '0';
                SD_DATA_VALID                                       <= '0';
                SD_RESET_TIMER                                      <= 0;
                SD_STATE                                            <= SD_STATE_RESET;
                IO_WAIT_SD                                          <= '0';

            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then

                -- Reset wait state, only 1 cycle long under normal circumstances.
                IO_WAIT_SD                                          <= '0';
    
                -- CPU Write?
                if MEM_WRITE_ENABLE = '1' and SD_CS = '1' then

                    -- Write to the SPI.
                    case MEM_ADDR(3 downto 2) is
                        when "00"  => -- Store address for next block operation.
                            SD_ADDR(tChannel)                       <= MEM_DATA_WRITE;

                        -- Write data latch, the host writes data to be written into this register when
                        -- the status register SD_DATA_REQ is set.
                        when "01"  =>
                            SD_DATA_WRITE                           <= MEM_DATA_WRITE(7 downto 0);
                            SD_DATA_REQ                             <= '0';

                        -- Command register, initiate transactions by setting the control bits.
                        when "11"  => -- Command
                            if MEM_DATA_WRITE(0) = '1' then
                                SD_STATE                            <= SD_STATE_RESET;
                            elsif MEM_DATA_WRITE(1) = '1' then
                                SD_STATE                            <= SD_STATE_WRITE;
                            elsif MEM_DATA_WRITE(2) = '1' then
                                SD_STATE                            <= SD_STATE_READ;
                            elsif MEM_DATA_WRITE(3) = '1' then
                                SD_CARD_TYPE(tChannel)              <= MEM_DATA_WRITE(7);
                            end if;
                            SD_CHANNEL                              <= tChannel;
                        
                        when others =>
                    end case;

                -- IO Read?
                elsif MEM_READ_ENABLE = '1' and SD_CS = '1' then

                    -- Read from SPI.
                    IO_DATA_READ_SD                                 <= (others => '0');
                    case MEM_ADDR(3 downto 2) is
                        -- Read back stored address.
                        when "00"  =>
                            IO_DATA_READ_SD                         <= SD_ADDR(tChannel);
                            IO_WAIT_SD                              <= '0';

                        -- Read Data, only valid if the SD_DATA_VALID bit is set.
                        when "01"  =>
                            IO_WAIT_SD                              <= '0';
                            IO_DATA_READ_SD(31 downto 16)           <= SD_ERROR(tChannel);
                            IO_DATA_READ_SD(7 downto 0)             <= SD_DATA_READ(tChannel);
                            SD_DATA_VALID                           <= '0';

                        -- Card status
                        when "11"  =>
                            IO_DATA_READ_SD(0)                      <= SD_CONTINUE(tChannel);
                            IO_DATA_READ_SD(1)                      <= SD_BUSY(tChannel);
                            IO_DATA_READ_SD(2)                      <= SD_HNDSHK_OUT(tChannel);
                            IO_DATA_READ_SD(3)                      <= SD_HNDSHK_IN(tChannel);
                            IO_DATA_READ_SD(4)                      <= SD_DATA_REQ;                    -- 1 when data needed for transmission.
                            IO_DATA_READ_SD(5)                      <= SD_DATA_VALID;                  -- 1 when data available.
                            IO_DATA_READ_SD(6)                      <= SD_OVERRUN;
                            IO_DATA_READ_SD(12 downto 8)            <= std_logic_vector(to_unsigned(SDStateType'POS(SD_STATE), 5));
                            IO_DATA_READ_SD(13)                     <= SD_RD(tChannel);
                            IO_DATA_READ_SD(14)                     <= SD_WR(tChannel);
                            IO_DATA_READ_SD(15)                     <= SD_RESET(tChannel);
                            IO_DATA_READ_SD(31 downto 16)           <= SD_ERROR(tChannel);
                            IO_WAIT_SD                              <= '0';
                            SD_OVERRUN                              <= '0'; 

                        when others =>
                    end case;
                end if;

                -- State machine to process requests.
                case SD_STATE is
                    when SD_STATE_IDLE =>
                        SD_RESET                                    <= (others => '0');
                        SD_WR                                       <= (others => '0');
                        SD_RD                                       <= (others => '0');

                    -----------------------------------------
                    -- RESET SD card
                    -----------------------------------------

                    -- To reset the card we apply a 100ns reset pulse, the card will then go through the reset procedure, asserting
                    -- BUSY until it is ready when BUSY will be deasserted.
                    when SD_STATE_RESET =>
                        SD_RESET_TIMER                              <= SYSCLK_FREQUENCY/10000000;
                        SD_RESET(SD_CHANNEL)                        <= '1';
                        SD_STATE                                    <= SD_STATE_RESET_1;

                    when SD_STATE_RESET_1 =>
                        if SD_RESET_TIMER = 0 then
                            SD_RESET(SD_CHANNEL)                    <= '0';
                            SD_STATE                                <= SD_STATE_IDLE;
                        else
                            SD_RESET_TIMER                          <= SD_RESET_TIMER - 1;
                        end if;

                    -----------------------------------------
                    -- WRITE a sector
                    -----------------------------------------
    
                    -- Address of byte (SD)/block (SDHC) already applied to address input. Set SD_WR high and wait
                    -- wait until SD_BUSY goes high.
                    when SD_STATE_WRITE =>
                        SD_WR(SD_CHANNEL)                           <= '1';
                        SD_DATA_REQ                                 <= '0';
                        if SD_BUSY(SD_CHANNEL) = '1' then
                            SD_WR(SD_CHANNEL)                       <= '0';
                            SD_STATE                                <= SD_STATE_WRITE_1;
                        end if;
    
                    -- We now enter a loop, we wait for a byte to be written into the data register, then wait for the controller
                    -- to assert HNDSHK_OUT, we raise the handshake line HNDSHK_IN and wait for the deassertion of HNDSHK_OUT to indicate completion.
                    -- If SD_BUSY is reset then it indicates completion, either due to an error or because the entire sector was written.
                    when SD_STATE_WRITE_1 =>
                        -- When DATA Request is clear and the controller starts a handshake, request from the host a byte.
                        if SD_DATA_REQ = '0' and SD_HNDSHK_OUT(SD_CHANNEL) = '1' then
                            SD_DATA_REQ                             <= '1';
                            SD_STATE                                <= SD_STATE_WRITE_2;

                        -- If Busy goes inactive then we have completed, either due to an error or completion of the write.
                        elsif SD_BUSY(SD_CHANNEL) = '0' then
                            SD_STATE                                <= SD_STATE_IDLE;
                        end if;
    
                    when SD_STATE_WRITE_2 =>
                        -- When the data byte is loaded by the host, we raise our handshake line to show data available.
                        if SD_DATA_REQ = '0' and SD_HNDSHK_OUT(SD_CHANNEL) = '1' then
                            SD_HNDSHK_IN(SD_CHANNEL)                <= '1';

                        -- When the controller acknowledges, lower the handshake line to complete the transaction.
                        elsif SD_HNDSHK_OUT(SD_CHANNEL) = '0' then
                            SD_HNDSHK_IN(SD_CHANNEL)                <= '0';
                            SD_STATE                                <= SD_STATE_WRITE_1;

                        elsif SD_BUSY(SD_CHANNEL) = '0' then
                            SD_STATE                                <= SD_STATE_IDLE;
                        end if;
    
                    -----------------------------------------
                    -- READ a sector
                    -----------------------------------------

                    -- For a read, we raise the SD_RD line and wait for SD_BUSY to go high. Once SD_BUSY is high, SD_RD is deasserted and we 
                    -- now wait for data.
                    when SD_STATE_READ =>
                        SD_RD(SD_CHANNEL)                           <= '1';
                        SD_DATA_VALID                               <= '0';
                        if SD_BUSY(SD_CHANNEL) = '1' then
                            SD_RD(SD_CHANNEL)                       <= '0';
                            SD_STATE                                <= SD_STATE_READ_1;
                        end if;
    
                    -- If SD_BUSY is ever deasserted, we are either at the end of a read or an error occurred, in either case exit to IDLE.
                    -- We wait for the HNDSHK_OUT to be asserted, read the data, and then move to the next state. In between, if the timeout
                    -- timer expires because the controller hasnt sent data, abort as it may have locked up.
                    when SD_STATE_READ_1 =>
    
                        if SD_HNDSHK_OUT(SD_CHANNEL) = '1' then
                            SD_DATA_VALID                           <= '1';
                            SD_HNDSHK_IN(SD_CHANNEL)                <= '1';
                            SD_STATE                                <= SD_STATE_READ_2;

                        elsif SD_BUSY(SD_CHANNEL) = '0' then
                            SD_STATE                                <= SD_STATE_IDLE;

                        elsif SD_DATA_VALID = '1' and SD_OVERRUN = '0' then
                            SD_OVERRUN                              <= '1';
                        end if;

                    -- Wait until the host reads the data, then assert HNDSHK_IN, the controller acknowledges by deasserting HNDSHK_OUT and at this
                    -- point the byte read cycle is complete so we deassert HNDSHK_IN. If the timeut expires during this operation or SD_BUSY is
                    -- deasserted, exit to IDLE due to error.
                    when SD_STATE_READ_2 =>

                        if SD_HNDSHK_OUT(SD_CHANNEL) = '0' and SD_DATA_VALID = '0' then
                            SD_HNDSHK_IN(SD_CHANNEL)                <= '0';
                            SD_STATE                                <= SD_STATE_READ_1;

                        elsif SD_BUSY(SD_CHANNEL) = '0' then
                            SD_STATE                                <= SD_STATE_IDLE;
    
                        end if;
                        
                    when others =>
                end case;
            end if;
        end process;
    end generate;

    -- Interrupt controller
    INTRCTL: if SOC_IMPL_INTRCTL = true generate
        INTCONTROLLER : entity work.interrupt_controller
            generic map (
                max_int              => INTR_MAX
            )
            port map (
                clk                  => SYSCLK,
                reset_n              => RESET_n,
                trigger              => INT_TRIGGERS,
                enable_mask          => INT_ENABLE,
                ack                  => INT_DONE,
                int                  => INT_REQ,
                status               => INT_STATUS
            );
    
        INT_TRIGGERS                 <= ( 0      => '0',
                                          1      => MICROSEC_DOWN_INTR,
                                          2      => MILLISEC_DOWN_INTR,
                                          3      => SECOND_DOWN_INTR,
                                          4      => TIMER1_TICK,
                                          5      => PS2_INT,
                                          6      => IOCTL_RDINT,
                                          7      => IOCTL_WRINT,
                                          8      => UART0_RX_INTR,
                                          9      => UART0_TX_INTR,
                                         10      => UART1_RX_INTR,
                                         11      => UART1_TX_INTR,
                                         others  => '0');
        INT_TRIGGER                  <= INT_REQ;    

        INTR0_CS                     <= '1' when IO_SELECT = '1'   and MEM_ADDR(11 downto 4) = "10110000"  -- Interrupt Range 0xFFFFFBxx, 0xB00-B0F
                                        else '0';
    end generate;
    NOINTRCTL: if SOC_IMPL_INTRCTL = false generate
        INT_TRIGGER                  <= '0';
    end generate;

    -- UART
    UART0 : entity work.uart
        generic map (
            RX_FIFO_BIT_DEPTH        => MAX_RX_FIFO_BITS,
            TX_FIFO_BIT_DEPTH        => MAX_TX_FIFO_BITS,
            COUNTER_BITS             => 16
        )
        port map (
            -- CPU Interface
            CLK                      => SYSCLK,                          -- memory master clock
            RESET                    => not RESET_n,                     -- high active sync reset
            ADDR                     => MEM_ADDR(3 downto 2),            -- 0 = Read/Write Data, 1 = Control Register, 3 = Baud Register
            DATA_IN                  => MEM_DATA_WRITE,                  -- write data
            DATA_OUT                 => UART0_DATA_OUT,                  -- read data
            CS                       => UART0_CS,                        -- Chip Select.
            WREN                     => MEM_WRITE_ENABLE,                -- Write enable.
            RDEN                     => MEM_READ_ENABLE,                 -- Read enable.
    
            -- IRQ outputs
            TXINTR                   => UART0_TX_INTR,                   -- Tx buffer empty interrupt.
            RXINTR                   => UART0_RX_INTR,                   -- Rx buffer full interrupt.
    
            -- Serial data
            TXD                      => UART_TX_0,
            RXD                      => UART_RX_0
        );

    UART1 : entity work.uart
        generic map (
            RX_FIFO_BIT_DEPTH        => MAX_RX_FIFO_BITS,
            TX_FIFO_BIT_DEPTH        => MAX_TX_FIFO_BITS,
            COUNTER_BITS             => 16
        )
        port map (
            -- CPU Interface
            CLK                      => SYSCLK,                          -- memory master clock
            RESET                    => not RESET_n,                     -- high active sync reset
            ADDR                     => MEM_ADDR(3 downto 2),            -- 0 = Read/Write Data, 1 = Control Register, 3 = Baud Register
            DATA_IN                  => MEM_DATA_WRITE,                  -- write data
            DATA_OUT                 => UART1_DATA_OUT,                  -- read data
            CS                       => UART1_CS,                        -- Chip Select.
            WREN                     => MEM_WRITE_ENABLE,                -- Write enable.
            RDEN                     => MEM_READ_ENABLE,                 -- Read enable.
    
            -- IRQ outputs
            TXINTR                   => UART1_TX_INTR,                   -- Tx buffer empty interrupt.
            RXINTR                   => UART1_RX_INTR,                   -- Rx buffer full interrupt.
    
            -- Serial data
            TXD                      => UART1_TX,
            RXD                      => UART_RX_1
        );

    -- IO Control Bus controller.
    IOCTL: if SOC_IMPL_IOCTL = true generate
        IOCTL0 : entity work.IOCTL
            port map (
                CLK                  => SYSCLK,                          -- memory master clock
                RESET                => not RESET_n,                     -- high active sync reset
                ADDR                 => MEM_ADDR(4 downto 2),            -- address bus.
                DATA_IN              => MEM_DATA_WRITE,                  -- write data
                DATA_OUT             => IOCTL_DATA_OUT,                  -- read data
                CS                   => IOCTL_CS,                        -- Chip Select.
                WREN                 => MEM_WRITE_ENABLE,                -- Write enable.
                RDEN                 => MEM_READ_ENABLE,                 -- Read enable.

                -- IRQ outputs --
                IRQ_RD_O             => IOCTL_RDINT,                     -- Read Interrupts from IOCTL.
                IRQ_WR_O             => IOCTL_WRINT,                     -- Write Interrupts from IOCTL.

                -- IOCTL Bus --
                IOCTL_DOWNLOAD       => IOCTL_DOWNLOAD,                  -- Downloading to FPGA.
                IOCTL_UPLOAD         => IOCTL_UPLOAD,                    -- Uploading from FPGA.
                IOCTL_CLK            => IOCTL_CLK,                       -- I/O Clock.
                IOCTL_WR             => IOCTL_WR,                        -- Write Enable to FPGA.
                IOCTL_RD             => IOCTL_RD,                        -- Read Enable from FPGA.
                IOCTL_SENSE          => IOCTL_SENSE,                     -- Sense to see if HPS accessing ioctl bus.
                IOCTL_SELECT         => IOCTL_SELECT,                    -- Enable IOP control over ioctl bus.
                IOCTL_ADDR           => IOCTL_ADDR,                      -- Address in FPGA to write into.
                IOCTL_DOUT           => IOCTL_DOUT,                      -- Data to be written into FPGA.
                IOCTL_DIN            => IOCTL_DIN                        -- Data to be read into HPS.
            );

        process(SYSCLK, RESET_n)
        begin
            ------------------------
            -- HIGH LEVEL         --
            ------------------------

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
                INT_ENABLE                                          <= (others => '0');
                IO_WAIT_INTR                                        <= '0';

            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then

                IO_WAIT_INTR                                        <= '0';

                -- CPU Write?
                if MEM_WRITE_ENABLE = '1' and INTR0_CS = '1' then

                    -- Write to interrupt controller sets the enable mask bits.
                    case MEM_ADDR(2) is
                        when '0' =>

                        when '1' =>
                            INT_ENABLE                              <= MEM_DATA_WRITE(INTR_MAX downto 0);
                    end case;

                -- IO Read?
                elsif MEM_READ_ENABLE = '1' and INTR0_CS = '1' then

                    -- Read interrupt status, 32 bits showing which interrupts have been triggered.
                    IO_DATA_READ_INTRCTL                            <= (others => '0');
                    if MEM_ADDR(2) = '0' then
                        IO_DATA_READ_INTRCTL(INTR_MAX downto 0)     <= INT_STATUS;
                    else
                        IO_DATA_READ_INTRCTL(INTR_MAX downto 0)     <= INT_ENABLE;
                    end if;

                end if;
            end if; -- rising-edge(SYSCLK)
        end process;

        IOCTL_CS  <= '1' when IO_SELECT = '1' and MEM_ADDR(11 downto 4) = "10000000"           -- Ioctl Range 0xFFFFF8xx 0x800-80F
                     else '0';
    end generate;

    IMPLSOCCFG: if SOC_IMPL_SOCCFG = true generate
        process(SYSCLK, RESET_n)
        begin
            ------------------------
            -- HIGH LEVEL         --
            ------------------------

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
    
            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then
    
                -- SoC Configuration.
                IO_DATA_READ_SOCCFG                                 <= (others => 'X');
                case MEM_ADDR(5 downto 2) is
                    when "0000" => -- ZPU Id
                        IO_DATA_READ_SOCCFG(31 downto 28)           <= "1010";                                                            -- Identifier to show SoC Configuration registers are implemented.
                        if ZPU_SMALL = 1 then
                            IO_DATA_READ_SOCCFG(15 downto 0)        <= std_logic_vector(to_unsigned(ZPU_ID_SMALL, 16));
                        elsif ZPU_MEDIUM = 1 then
                            IO_DATA_READ_SOCCFG(15 downto 0)        <= std_logic_vector(to_unsigned(ZPU_ID_MEDIUM, 16));
                        elsif ZPU_FLEX = 1 then
                            IO_DATA_READ_SOCCFG(15 downto 0)        <= std_logic_vector(to_unsigned(ZPU_ID_FLEX, 16));
                        elsif ZPU_EVO = 1 then
                            IO_DATA_READ_SOCCFG(15 downto 0)        <= std_logic_vector(to_unsigned(ZPU_ID_EVO, 16));
                        elsif ZPU_EVO_MINIMAL = 1 then
                            IO_DATA_READ_SOCCFG(15 downto 0)        <= std_logic_vector(to_unsigned(ZPU_ID_EVO_MINIMAL, 16));
                        end if;

                    when "0001" => -- System Frequency
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SYSCLK_FREQUENCY, wordSize));

                    when "0010" => -- Devices Implemented
                        IO_DATA_READ_SOCCFG(14 downto 0)            <= to_std_logic(SOC_IMPL_BRAM) & 
                                                                       to_std_logic(SOC_IMPL_RAM) & 
                                                                       to_std_logic(SOC_IMPL_INSN_BRAM) &
                                                                       to_std_logic(SOC_IMPL_DRAM) & 
                                                                       to_std_logic(SOC_IMPL_IOCTL) &
                                                                       to_std_logic(SOC_IMPL_PS2) & 
                                                                       to_std_logic(SOC_IMPL_SPI) & 
                                                                       to_std_logic(SOC_IMPL_SD) & 
                                                                       std_logic_vector(to_unsigned(SOC_SD_DEVICES, 2)) &
                                                                       to_std_logic(SOC_IMPL_INTRCTL) & 
                                                                       to_std_logic(SOC_IMPL_TIMER1) & 
                                                                       std_logic_vector(to_unsigned(2**SOC_TIMER1_COUNTERS, 3));

                    when "0011" => -- BRAM Address
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_ADDR_BRAM_START, wordSize));

                    when "0100" => -- BRAM Size
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_ADDR_BRAM_END - SOC_ADDR_BRAM_START, wordSize));

                    when "0101" => -- RAM Address
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_ADDR_RAM_START, wordSize));

                    when "0110" => -- RAM Size
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_ADDR_RAM_END - SOC_ADDR_RAM_START, wordSize));

                    when "0111" => -- Instruction BRAM Address
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_ADDR_INSN_BRAM_START, wordSize));

                    when "1000" => -- Instruction BRAM Size
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_ADDR_INSN_BRAM_END - SOC_ADDR_INSN_BRAM_START, wordSize));

                    when "1001" => -- CPU Reset Address
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_RESET_ADDR_CPU, wordSize));

                    when "1010" => -- CPU Memory Start Address
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_START_ADDR_MEM, wordSize));

                    when "1011" => -- Stack Start Address
                        IO_DATA_READ_SOCCFG                         <= std_logic_vector(to_unsigned(SOC_STACK_ADDR, wordSize));

                    when others =>
                end case;
            end if; -- rising-edge(SYSCLK)
        end process;

        SOCCFG_CS             <= '1' when IO_SELECT = '1' and MEM_ADDR(11 downto 6) = "111100"        -- SoC COnfig Range 0xF00-F40, step 4 for 32 bit registers.
                                 else '0';
    end generate;

    IMPLIOCTL: if SOC_IMPL_IOCTL = true generate
        process(SYSCLK, RESET_n)
        begin
            ------------------------
            -- HIGH LEVEL         --
            ------------------------

            ------------------------
            -- ASYNCHRONOUS RESET --
            ------------------------
            if RESET_n='0' then
                IO_WAIT_IOCTL                                       <= '0';

            -----------------------
            -- RISING CLOCK EDGE --
            -----------------------                
            elsif rising_edge(SYSCLK) then

                IO_WAIT_IOCTL                                       <= '0';

                -- CPU Write?
                if MEM_WRITE_ENABLE = '1' and IO_SELECT = '1' then

                -- IO Read?
                elsif MEM_READ_ENABLE = '1' and IO_SELECT = '1' then

                    if IOCTL_CS = '1' then
                        IO_DATA_READ_IOCTL                          <= IOCTL_DATA_OUT;
                    end if;

                end if;
            end if; -- rising-edge(SYSCLK)
        end process;
    end generate;
    ------------------------------------------------------------------------------------
    -- END Direct I/O devices
    ------------------------------------------------------------------------------------

    ------------------------------------------------------------------------------------
    -- WISHBONE devices
    ------------------------------------------------------------------------------------

    I2C : if (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and SOC_IMPL_WB_I2C = true generate
        I2C_MASTER_0: work.i2c_master_top
        generic map (
            ARST_LVL             => '1' -- asynchronous reset level
        )
        port map (
            -- Wishbone Bus
            wb_clk_i             => SYSCLK,                         -- master clock input
            wb_rst_i             => not RESET_n,                    -- synchronous active high reset
            arst_i               => '0',                            -- asynchronous reset - not used.
            wb_adr_i             => WB_ADR_O(4 downto 2),           -- lower address bits
            wb_dat_i             => WB_DAT_O(BYTE_RANGE),           -- Databus input (lowest 8 bit)
            wb_dat_o             => WB_DATA_READ_I2C(BYTE_RANGE),   -- Databus output
            wb_we_i              => WB_WE_O,                        -- Write enable input
            wb_stb_i             => WB_I2C_CS,                      -- Strobe signal using chip select.
            wb_cyc_i             => WB_CYC_O,                       -- Valid bus cycle input
            wb_ack_o             => WB_I2C_ACK,                     -- Bus cycle acknowledge output
            wb_inta_o            => WB_I2C_IRQ,                     -- interrupt request output signal
                    
            -- I²C lines
            scl_pad_i            => SCL_PAD_IN,                     -- i2c clock line input
            scl_pad_o            => SCL_PAD_OUT,                    -- i2c clock line output
            scl_padoen_o         => SCL_PAD_OE,                     -- i2c clock line output enable, active low
            sda_pad_i            => SDA_PAD_IN,                     -- i2c data line input
            sda_pad_o            => SDA_PAD_OUT,                    -- i2c data line output
            sda_padoen_o         => SDA_PAD_OE                      -- i2c data line output enable, active low
        );

        -- Data Width Adaption, I2C is only 8 bits so expand to 32bits.
        --WB_DATA_READ_I2C         <= x"000000" & I2C_DATA_OUT;

        -- IO Buffer
        I2C_SCL_IO               <= SCL_PAD_OUT when (SCL_PAD_OE = '0') else 'Z';
        I2C_SDA_IO               <= SDA_PAD_OUT when (SDA_PAD_OE = '0') else 'Z';
        SCL_PAD_IN               <= I2C_SCL_IO;
        SDA_PAD_IN               <= I2C_SDA_IO;

        -- Halt / Error
        WB_I2C_HALT              <= '0';                            -- no throttle -> full speed
        WB_I2C_ERR               <= '0';                            -- nothing can go wrong - never ever!
    end generate;

    -- SDRAM over WishBone bus.
    ZPUSDRAMEVO : if (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and SOC_IMPL_WB_SDRAM = true generate

        ZPUSDRAM : entity work.SDRAM
            port map (
                -- SDRAM Interface
                SD_CLK           => SYSCLK,           -- sdram is accessed at 100MHz
                SD_RST           => not RESET_n,      -- reset the sdram controller.
                SD_CKE           => SDRAM_CKE,        -- clock enable.
                SD_DQ            => SDRAM_DQ,         -- 16 bit bidirectional data bus
                SD_ADDR          => SDRAM_ADDR,       -- 13 bit multiplexed address bus
                SD_DQM           => SDRAM_DQM,        -- two byte masks
                SD_BA            => SDRAM_BA,         -- two banks
                SD_CS_n          => SDRAM_CS_n,       -- a single chip select
                SD_WE_n          => SDRAM_WE_n,       -- write enable
                SD_RAS_n         => SDRAM_RAS_n,      -- row address select
                SD_CAS_n         => SDRAM_CAS_n,      -- columns address select
                SD_READY         => SDRAM_READY,      -- sd ready.

                -- WishBone interface.
                WB_CLK           => WB_CLK_I,         -- 100MHz chipset clock to which sdram state machine is synchonized    
                WB_DAT_I         => WB_DAT_O,         -- data input from chipset/cpu
                WB_DAT_O         => WB_DATA_READ_SDRAM, -- data output to chipset/cpu
                WB_ACK_O         => WB_SDRAM_ACK, 
                WB_ADR_I         => WB_ADR_O(23 downto 0), -- lower 2 bits are ignored.
                WB_SEL_I         => WB_SEL_O, 
                WB_CTI_I         => WB_CTI_O,         -- cycle type. 
                WB_STB_I         => WB_SDRAM_STB, 
                WB_CYC_I         => WB_CYC_O,         -- cpu/chipset requests cycle
                WB_WE_I          => RAM_WREN          -- cpu/chipset requests write   
            );
--
--        ZPUSRAM: entity work.SRAM
--            generic map (
--                addrbits      => 14
--            )        
--            port map (
--                -- WishBone interface.
--                WB_CLK_I         => WB_CLK_I,         -- 100MHz chipset clock to which sdram state machine is synchonized    
--                WB_RST_I         => not RESET_n,      -- high active sync reset
--                WB_DATA_I        => WB_DAT_O,         -- data input from chipset/cpu
--                WB_DATA_O        => WB_DATA_READ_SDRAM, -- data output to chipset/cpu
--                WB_ACK_O         => WB_SDRAM_ACK, 
--                WB_ADR_I         => WB_ADR_O(13 downto 0), -- lower 2 bits are ignored.
--                WB_SEL_I         => WB_SEL_O, 
--                WB_CTI_I         => WB_CTI_O,         -- cycle type. 
--                WB_STB_I         => WB_SDRAM_STB, 
--                WB_CYC_I         => WB_CYC_O,         -- cpu/chipset requests cycle
--                WB_WE_I          => RAM_WREN,         -- cpu/chipset requests write   
--                WB_TGC_I         => "0000000",        -- cycle tag
--                WB_HALT_O        => open,
--                WB_ERR_O         => open
--            );

        -- RAM Range SOC_ADDR_RAM_START) -> SOC_ADDR_RAM_END
        RAM_SELECT               <= '1' when (ZPU_EVO = 1 or ZPU_EVO_MINIMAL = 1) and (WB_ADR_O >= std_logic_vector(to_unsigned(SOC_ADDR_RAM_START, WB_ADR_O'LENGTH)) and WB_ADR_O < std_logic_vector(to_unsigned(SOC_ADDR_RAM_END, WB_ADR_O'LENGTH)))
                                    else '0';

        -- Enable write to RAM when selected and CPU in write state.
        RAM_WREN                 <= '1' when RAM_SELECT = '1' and WB_WE_O = '1'
                                    else
                                    '0';

        -- Wishbone strobe based on the RAM Select signal which limits the address range.
        WB_SDRAM_STB             <= '1' when RAM_SELECT = '1' and WB_STB_O = '1'
                                    else '0';

        -- SDRAM clock based on system clock.
        SDRAM_CLK                <= SYSCLK;
    end generate;

    ------------------------------------------------------------------------------------
    -- END WISHBONE devices
    ------------------------------------------------------------------------------------


    -- Reset counter. Incoming reset toggles reset and holds it low for a fixed period. Additionally, if the primary UART RX receives a break
    -- signal, then the reset is triggered.
    --
    process(SYSCLK, RESET_IN)
    begin
        ------------------------
        -- HIGH LEVEL         --
        ------------------------

        ------------------------
        -- ASYNCHRONOUS RESET --
        ------------------------
        if RESET_IN='0' then
            RESET_COUNTER                                           <= X"FFFF";
            RESET_COUNTER_RX                                        <= to_unsigned(((SYSCLK_FREQUENCY*100000)/300)*8, 16);
            RESET_n                                                 <= '0';

        -----------------------
        -- RISING CLOCK EDGE --
        -----------------------                
        elsif rising_edge(SYSCLK) then

            -- If the RX receives a break signal, count down to ensure it is held low for correct period, when the count reaches
            -- zero, start a reset.
            --
            if UART_RX_0 = '0' or UART_RX_1 = '0' then
                RESET_COUNTER_RX                                    <= RESET_COUNTER_RX - 1;
            else
                RESET_COUNTER_RX                                    <= to_unsigned(((SYSCLK_FREQUENCY*100000)/300)*8, 16);
            end if;

            if RESET_COUNTER_RX = X"0000" then
                RESET_COUNTER                                       <= X"FFFF";
                RESET_COUNTER_RX                                    <= to_unsigned(((SYSCLK_FREQUENCY*100000)/300)*8, 16);
                RESET_n                                             <= '0';
            end if;

            RESET_COUNTER                                           <= RESET_COUNTER - 1;
            if RESET_COUNTER = X"0000" then
                RESET_n                                             <= '1';
            end if;
        end if;
    end process;
    
    -- Main peripheral process, decode address and activate memory/peripheral accordingly.        
    process(SYSCLK, RESET_n)
    begin
        ------------------------
        -- HIGH LEVEL         --
        ------------------------

        ------------------------
        -- ASYNCHRONOUS RESET --
        ------------------------
        if RESET_n='0' then
            MICROSEC_DOWN_COUNTER                                   <= (others => '0');
            MILLISEC_DOWN_COUNTER                                   <= (others => '0');
            MILLISEC_UP_COUNTER                                     <= (others => '0');
            SECOND_DOWN_COUNTER                                     <= (others => '0');
            MICROSEC_DOWN_TICK                                      <= 0;
            MILLISEC_DOWN_TICK                                      <= 0;
            SECOND_DOWN_TICK                                        <= 0;
            MILLISEC_UP_TICK                                        <= 0;
            MICROSEC_DOWN_INTR                                      <= '0';
            MICROSEC_DOWN_INTR_EN                                   <= '0';
            MILLISEC_DOWN_INTR                                      <= '0';
            MILLISEC_DOWN_INTR_EN                                   <= '0';
            SECOND_DOWN_INTR                                        <= '0';
            SECOND_DOWN_INTR_EN                                     <= '0';
            RTC_MICROSEC_TICK                                       <= 0;
            RTC_MICROSEC_COUNTER                                    <= 0;
            RTC_MILLISEC_COUNTER                                    <= 0;
            RTC_SECOND_COUNTER                                      <= 0;
            RTC_MINUTE_COUNTER                                      <= 0;
            RTC_HOUR_COUNTER                                        <= 0;
            RTC_DAY_COUNTER                                         <= 1;
            RTC_MONTH_COUNTER                                       <= 1;
            RTC_YEAR_COUNTER                                        <= 0;
            RTC_TICK_HALT                                           <= '0';

        -----------------------
        -- RISING CLOCK EDGE --
        -----------------------                
        elsif rising_edge(SYSCLK) then

            -- CPU Write?
            if MEM_WRITE_ENABLE = '1' and IO_SELECT = '1' then

                -- Write to Millisecond Timer - set current time and day.
                if TIMER0_CS = '1' then
                    case MEM_ADDR(5 downto 2) is
                        when "0000" =>
                            MICROSEC_DOWN_COUNTER(23 downto 0)      <= unsigned(MEM_DATA_WRITE(23 downto 0));
                            MICROSEC_DOWN_TICK                      <= 0;

                        when "0001" =>
                            MILLISEC_DOWN_COUNTER(17 downto 0)      <= unsigned(MEM_DATA_WRITE(17 downto 0));
                            MILLISEC_DOWN_TICK                      <= 0;

                        when "0010" =>
                            MILLISEC_UP_COUNTER(31 downto 0)        <= unsigned(MEM_DATA_WRITE(31 downto 0));
                            MILLISEC_UP_TICK                        <= 0;

                        when "0011" =>
                            SECOND_DOWN_COUNTER(11 downto 0)        <= unsigned(MEM_DATA_WRITE(11 downto 0));
                            SECOND_DOWN_TICK                        <= 0;

                        when "0111" =>
                            RTC_TICK_HALT                           <= MEM_DATA_WRITE(0);

                        when "1000" =>
                            RTC_MICROSEC_COUNTER                    <= to_integer(unsigned(MEM_DATA_WRITE(9 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1001" =>
                            RTC_MILLISEC_COUNTER                    <= to_integer(unsigned(MEM_DATA_WRITE(9 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1010" =>
                            RTC_SECOND_COUNTER                      <= to_integer(unsigned(MEM_DATA_WRITE(5 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1011" =>
                            RTC_MINUTE_COUNTER                      <= to_integer(unsigned(MEM_DATA_WRITE(5 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1100" =>
                            RTC_HOUR_COUNTER                        <= to_integer(unsigned(MEM_DATA_WRITE(4 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1101" =>
                            RTC_DAY_COUNTER                         <= to_integer(unsigned(MEM_DATA_WRITE(3 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1110" =>
                            RTC_MONTH_COUNTER                       <= to_integer(unsigned(MEM_DATA_WRITE(3 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when "1111" =>
                            RTC_YEAR_COUNTER                        <= to_integer(unsigned(MEM_DATA_WRITE(11 downto 0)));
                            RTC_MICROSEC_TICK                       <= 0;

                        when others =>
                    end case;
                end if;
            end if;

            -- Read from UART.
            if UART0_CS = '1' then
                IO_DATA_READ                                        <= UART0_DATA_OUT;
            end if;
            if UART1_CS = '1' then
                IO_DATA_READ                                        <= UART1_DATA_OUT;
            end if;

            -- Read from millisecond timer, read milliseconds in last 24 hours and number of elapsed days.
            if TIMER0_CS = '1' then
                IO_DATA_READ                                        <= (others => '0');
                case MEM_ADDR(5 downto 2) is
                    when "0000" =>
                        IO_DATA_READ(23 downto 0)                   <= std_logic_vector(MICROSEC_DOWN_COUNTER(23 downto 0));

                    when "0001" =>
                        IO_DATA_READ(17 downto 0)                   <= std_logic_vector(MILLISEC_DOWN_COUNTER(17 downto 0));

                    when "0010" =>
                        IO_DATA_READ(31 downto 0)                   <= std_logic_vector(MILLISEC_UP_COUNTER(31 downto 0));

                    when "0011" =>
                        IO_DATA_READ(11 downto 0)                   <= std_logic_vector(SECOND_DOWN_COUNTER(11 downto 0));

                    when "1000" =>
                        IO_DATA_READ(9 downto 0)                    <= std_logic_vector(to_unsigned(RTC_MICROSEC_COUNTER, 10));

                    when "1001" =>
                        IO_DATA_READ(9 downto 0)                    <= std_logic_vector(to_unsigned(RTC_MILLISEC_COUNTER, 10));

                    when "1010" =>
                        IO_DATA_READ(5 downto 0)                    <= std_logic_vector(to_unsigned(RTC_SECOND_COUNTER, 6));

                    when "1011" =>
                        IO_DATA_READ(5 downto 0)                    <= std_logic_vector(to_unsigned(RTC_MINUTE_COUNTER, 6));

                    when "1100" =>
                        IO_DATA_READ(4 downto 0)                    <= std_logic_vector(to_unsigned(RTC_HOUR_COUNTER, 5));

                    when "1101" =>
                        IO_DATA_READ(4 downto 0)                    <= std_logic_vector(to_unsigned(RTC_DAY_COUNTER, 5));

                    when "1110" =>
                        IO_DATA_READ(3 downto 0)                    <= std_logic_vector(to_unsigned(RTC_MONTH_COUNTER, 4));

                    when "1111" =>
                        IO_DATA_READ(11 downto 0)                   <= std_logic_vector(to_unsigned(RTC_YEAR_COUNTER, 12));

                    when others =>
                end case;
            end if;

            -- Timer in microseconds, Each 24 hours the timer is zeroed and the day counter incremented. Used for delay loops
            -- and RTC.
            if RTC_TICK_HALT = '0' then
                RTC_MICROSEC_TICK                                   <= RTC_MICROSEC_TICK+1;
            end if;
            if RTC_MICROSEC_TICK = (SYSCLK_FREQUENCY/(SYSCLK_FREQUENCY/100)) then               -- Sys clock has to be > 1MHz or will not be accurate.
                RTC_MICROSEC_TICK                                   <= 0;
                RTC_MICROSEC_COUNTER                                <= RTC_MICROSEC_COUNTER + 1;
            end if;
            if RTC_MICROSEC_COUNTER = 1000 then
                RTC_MICROSEC_COUNTER                                <= 0;
                RTC_MILLISEC_COUNTER                                <= RTC_MILLISEC_COUNTER + 1;
            end if;
            if RTC_MILLISEC_COUNTER = 1000 then
                RTC_SECOND_COUNTER                                  <= RTC_SECOND_COUNTER + 1; 
                RTC_MILLISEC_COUNTER                                <= 0;
            end if;
            if RTC_SECOND_COUNTER = 60 then
                RTC_MINUTE_COUNTER                                  <= RTC_MINUTE_COUNTER + 1;
                RTC_SECOND_COUNTER                                  <= 0;
            end if;
            if RTC_MINUTE_COUNTER = 60 then
                RTC_HOUR_COUNTER                                    <= RTC_HOUR_COUNTER + 1;
                RTC_MINUTE_COUNTER                                  <= 0;
            end if;
            if RTC_HOUR_COUNTER = 24 then
                RTC_DAY_COUNTER                                     <= RTC_DAY_COUNTER + 1;
                RTC_HOUR_COUNTER                                    <= 0;
            end if;
            if (RTC_DAY_COUNTER = 31 and (RTC_MONTH_COUNTER = 4 or RTC_MONTH_COUNTER = 6 or RTC_MONTH_COUNTER = 9 or RTC_MONTH_COUNTER = 11)) 
               or
               (RTC_DAY_COUNTER = 32 and RTC_MONTH_COUNTER /= 4 and RTC_MONTH_COUNTER /= 6 and RTC_MONTH_COUNTER /= 9 and RTC_MONTH_COUNTER /= 11)
               or
               (RTC_DAY_COUNTER = 29 and RTC_MONTH_COUNTER = 2 and std_logic_vector(to_unsigned(RTC_YEAR_COUNTER, 2)) /= "00")
               or
               (RTC_DAY_COUNTER = 30 and RTC_MONTH_COUNTER = 2 and std_logic_vector(to_unsigned(RTC_YEAR_COUNTER, 2))  = "00")
            then
                RTC_MONTH_COUNTER                                   <= RTC_MONTH_COUNTER + 1;
                RTC_DAY_COUNTER                                     <= 1;
            end if;
            if RTC_MONTH_COUNTER = 13 then
                RTC_YEAR_COUNTER                                    <= RTC_YEAR_COUNTER + 1;
                RTC_MONTH_COUNTER                                   <= 1;
            end if;

            -- Down and up counters, each have independent ticks which reset on counter set, this guarantees timer is accurate.
            MICROSEC_DOWN_TICK                                      <= MICROSEC_DOWN_TICK+1;
            if MICROSEC_DOWN_TICK = (SYSCLK_FREQUENCY/(SYSCLK_FREQUENCY/100)) then               -- Sys clock has to be > 1MHz or will not be accurate.
                MICROSEC_DOWN_TICK                                  <= 0;

                -- Decrement microsecond down counter if not yet zero.
                if MICROSEC_DOWN_COUNTER /= 0 then
                    MICROSEC_DOWN_COUNTER                           <= MICROSEC_DOWN_COUNTER - 1;
                end if;
                if MICROSEC_DOWN_COUNTER = 0 and MICROSEC_DOWN_INTR_EN = '1' then
                    MICROSEC_DOWN_INTR                              <= '1';
                end if;
            end if;

            MILLISEC_DOWN_TICK                                      <= MILLISEC_DOWN_TICK+1;
            if MILLISEC_DOWN_TICK = (SYSCLK_FREQUENCY/(SYSCLK_FREQUENCY/100))*1000 then          -- Sys clock has to be > 1MHz or will not be accurate.
                MILLISEC_DOWN_TICK                                  <= 0;

                -- Decrement millisecond down counter if not yet zero.
                if MILLISEC_DOWN_COUNTER /= 0 then
                    MILLISEC_DOWN_COUNTER                           <= MILLISEC_DOWN_COUNTER - 1;
                end if;
                if MILLISEC_DOWN_COUNTER = 0 and MILLISEC_DOWN_INTR_EN = '1' then
                    MILLISEC_DOWN_INTR                              <= '1';
                end if;
            end if;

            MILLISEC_UP_TICK                                        <= MILLISEC_UP_TICK+1;
            if MILLISEC_UP_TICK = (SYSCLK_FREQUENCY/(SYSCLK_FREQUENCY/100))*1000 then            -- Sys clock has to be > 1MHz or will not be accurate.
                MILLISEC_UP_TICK                                    <= 0;
                MILLISEC_UP_COUNTER                                 <= MILLISEC_UP_COUNTER + 1;
            end if;

            SECOND_DOWN_TICK                                        <= SECOND_DOWN_TICK+1;
            if SECOND_DOWN_TICK = (SYSCLK_FREQUENCY/(SYSCLK_FREQUENCY/100))*1000000 then         -- Sys clock has to be > 1MHz or will not be accurate.
                SECOND_DOWN_TICK                                    <= 0;

                -- Decrement second down counter if not yet zero.
                if SECOND_DOWN_COUNTER /= 0 then
                    SECOND_DOWN_COUNTER                             <= SECOND_DOWN_COUNTER - 1;
                end if;
                if SECOND_DOWN_COUNTER = 0 and SECOND_DOWN_INTR_EN = '1' then
                    SECOND_DOWN_INTR                                <= '1';
                end if;
            end if;
        end if; -- rising-edge(SYSCLK)
    end process;

end architecture;
