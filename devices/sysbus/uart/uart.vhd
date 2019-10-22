---------------------------------------------------------------------------------------------------------
--
-- Name:            uart.vhd
-- Created:         January 2019
-- Author(s):       Philip Smart (based on the simplistic UART 
-- Description:     ZPU SOC IOCTL Interface to an Emulator (Sharp MZ series).
--                  This module interfaces the ZPU IO processor to the Emulator IO Control backdoor
--                  for updating ROM/RAM, OSD and providing IO services.
-- Credits:         Originally using the simplistic UART as a guide, which was written by the following
--                  authors:-
--                  Philippe Carton, philippe.carton2 libertysurf.fr
--                  Juan Pablo Daniel Borgna, jpdborgna gmail.com
--                  Salvador E. Tropea, salvador inti.gob.ar
-- Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
--
-- History:         January 2019  - Initial module written using the simplistic UART as a guide but
--                                  adding cache and more control.
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
use work.zpu_pkg.all;
use work.zpu_soc_pkg.all;

-- Based on the simplistic UART, handles 8N1 RS232 Rx/Tx with independent programmable baud rate and selectable FIFO buffers.
entity uart is
    generic (
        RX_FIFO_BIT_DEPTH     : integer := 10;
        TX_FIFO_BIT_DEPTH     : integer := 8;
        COUNTER_BITS          : natural := 16
    );
    port (
        -- CPU Interface
        CLK                   : in  std_logic;                                  -- memory master clock
        RESET                 : in  std_logic;                                  -- high active sync reset
        ADDR                  : in  std_logic_vector(1 downto 0);               -- 0 = Read/Write Data, 1 = Control Register, 3 = Baud Register
        DATA_IN               : in  std_logic_vector(wordSize-1 downto 0);      -- write data
        DATA_OUT              : out std_logic_vector(wordSize-1 downto 0);      -- read data
        CS                    : in  std_logic;                                  -- Chip Select.
        WREN                  : in  std_logic;                                  -- Write enable.
        RDEN                  : in  std_logic;                                  -- Read enable.

        -- IRQ outputs
        TXINTR                : out std_logic;                                  -- Tx buffer empty interrupt.
        RXINTR                : out std_logic;                                  -- Rx buffer full interrupt.

        -- Serial data
        TXD                   : out std_logic;
        RXD                   : in  std_logic
    );
end uart;

architecture rtl of uart is

signal RXD_SYNC               :     std_logic;
signal RXD_SYNC2              :     std_logic;

type RXSTATES is (idle, start, bits, stop);
signal RX_STATE : RXSTATES := idle;

signal RX_CLOCK_DIVISOR       :     unsigned(COUNTER_BITS-1 downto 0) := X"043D";    -- Main clock divisor to create RX Clock.
signal RX_COUNTER             :     unsigned(COUNTER_BITS-1 downto 0);               -- RX Clock generator counter.
signal RX_CLOCK               :     std_logic;                                       -- RX Clock.
signal RX_BUFFER              :     std_logic_vector(8 downto 0);                    -- Receive deserialisation buffer.
signal RX_DATA                :     std_logic_vector(7 downto 0);                    -- Received data holding register.
signal RX_DATA_READY          :     std_logic;                                       -- Byte available to read = 1
signal RX_OVERRUN             :     std_logic;                                       -- New byte received before previous read by CPU, old value lost.
signal RX_INTR                :     std_logic;                                       -- Rx buffer full interrupt.
signal RX_ENABLE              :     std_logic;                                       -- Enable RX unit.
signal RX_ENABLE_FIFO         :     std_logic;                                       -- Enable RX FIFO.
signal RX_RESET               :     std_logic;                                       -- Reset RX unit.
signal RX_FIFO_EMPTY          :     std_logic;                                       -- RX FIFO is empty = 1.
signal RX_FIFO_FULL           :     std_logic;                                       -- RX FIFO is full = 1.

type TXSTATES is (idle, bits);
signal TX_STATE : TXSTATES := idle;

signal TX_CLOCK_DIVISOR       :     unsigned(COUNTER_BITS-1 downto 0) := X"043D";    -- Main clock divisor to create TX Clock.
signal TX_BUFFER              :     std_logic_vector(17 downto 0);                   -- Transmit serialisation buffer.
signal TX_DATA                :     std_logic_vector(7 downto 0);                    -- Transmit holding register.
signal TX_DATA_LOADED         :     std_logic;                                       -- Data loaded into transmit buffer.
signal TX_BUSY                :     std_logic;                                       -- Transmit in progress.
signal TX_OVERRUN             :     std_logic;                                       -- TX write when last byte not sent or fifo full.
signal TX_COUNTER             :     unsigned(COUNTER_BITS-1 downto 0);               -- TX Clock generator counter.
signal TX_CLOCK               :     std_logic;                                       -- TX Clock.
signal TX_INTR                :     std_logic;                                       -- Tx buffer empty interrupt.
signal TX_ENABLE              :     std_logic;                                       -- Enable TX unit.
signal TX_ENABLE_FIFO         :     std_logic;                                       -- Enable TX FIFO.
signal TX_RESET               :     std_logic;                                       -- Reset TX unit.
signal TX_FIFO_EMPTY          :     std_logic;                                       -- TX FIFO is empty = 1.
signal TX_FIFO_FULL           :     std_logic;                                       -- TX FIFO is full = 1.

-- FIFO buffers.
type RX_MEM_T is array (0 to ((2**RX_FIFO_BIT_DEPTH)-1)) of std_logic_vector(7 downto 0);
type TX_MEM_T is array (0 to ((2**TX_FIFO_BIT_DEPTH)-1)) of std_logic_vector(7 downto 0);
signal RX_FIFO                :  RX_MEM_T;
signal TX_FIFO                :  TX_MEM_T;
-- RX Fifo address pointers.
signal RX_FIFO_WR_ADDR        :  unsigned(RX_FIFO_BIT_DEPTH-1 downto 0);
signal RX_FIFO_RD_ADDR        :  unsigned(RX_FIFO_BIT_DEPTH-1 downto 0);
-- TX Fifo address pointers.
signal TX_FIFO_WR_ADDR        :  unsigned(TX_FIFO_BIT_DEPTH-1 downto 0);
signal TX_FIFO_RD_ADDR        :  unsigned(TX_FIFO_BIT_DEPTH-1 downto 0);

begin

    -- Signal synchronisation for rxd.
    -- Without this, the state machine can get messed up.  The change from one state
    -- to another is not an atomic operation; leaving one state and entering the next
    -- are distinct, and it's possible (and, in fact, common) for one 
    -- to happen without the other if inputs aren't properly synchronised.
    process(CLK, RXD, RX_ENABLE)
    begin
        if RX_ENABLE = '1' and rising_edge(CLK) then
            RXD_SYNC2                  <= RXD;
            RXD_SYNC                   <= RXD_SYNC2;
        end if;
    end process;
    

    -- Clock generators.
    -- We have independent Rx and Tx clocks, generated from counters which count down from clock_divisor to zero.
    -- At zero, we generate a momentary high pulse which is used as the serial clock signal.

    -- Tx Clock generation
    -- Very simple - the counter is reset when either it reaches zero or
    -- the Tx is idle, and counts down once per system clock tick.
    process(CLK, TX_ENABLE, TX_CLOCK_DIVISOR)
    begin
        if TX_ENABLE = '1' and rising_edge(CLK) then
            TX_CLOCK                   <= '0';

            if TX_STATE = idle then
                TX_COUNTER             <= TX_CLOCK_DIVISOR;
            else
                TX_COUNTER             <= TX_COUNTER-1;
                if TX_COUNTER = 0 then
                    TX_CLOCK           <= '1';
                    TX_COUNTER         <= TX_CLOCK_DIVISOR;
                end if;
            end if;
        end if;
    end process;

    
    -- Rx Clock generation
    -- The Rx clock is slightly more complicated.  When idle we detect the leading edge of the
    -- start bit, and set the counter to half a bit width.  When it reaches zero, the counter is
    -- set to a full bit width, so clock ticks should land in the centre of each bit.
    process(clk,RXD_SYNC,RX_COUNTER,RX_STATE,RX_ENABLE)
    begin
        if RX_ENABLE = '1' and rising_edge(clk) then
            RX_CLOCK                   <= '0';

            if RX_STATE=idle then
                if RXD_SYNC='0' then    -- Start bit?  Set counter to half a bit width
                    RX_COUNTER         <= '0' & RX_CLOCK_DIVISOR(COUNTER_BITS-1 downto 1);
                end if;
            else
                RX_COUNTER<=RX_COUNTER-1;
                if RX_COUNTER=0 then
                    RX_CLOCK           <= '1';
                    RX_COUNTER         <= RX_CLOCK_DIVISOR;
                end if;
            end if;
        end if;
    end process;


    -- Data Rx
    -- We use a 9-bit shift register here.  Upon detection of the start bit, we
    -- load the shift register with "100000000".
    -- As each bit is received we shift the register one bit to the right, and load new data
    -- into bit 8.
    -- When the 1 initially in bit 8 reaches bit zero we know we've received the entire word.
    process(clk,RX_RESET,RXD_SYNC,RX_STATE,RX_FIFO_RD_ADDR,RX_FIFO_WR_ADDR,RX_ENABLE,RX_INTR)
        variable RX_FULL_V    : std_logic;
        variable RX_EMPTY_V   : std_logic;
    begin

        if RX_RESET='1' then
            RX_STATE                   <= idle;
            RX_INTR                    <= '0';
            RX_DATA_READY              <= '0';
            RX_OVERRUN                 <= '0';
            RX_FIFO_WR_ADDR            <= (others => '0');
            RX_FIFO_RD_ADDR            <= (others => '0');
            RX_FIFO_EMPTY              <= '1';
            RX_FIFO_FULL               <= '0';

        elsif RX_ENABLE = '1' and rising_edge(clk) then

            -- Interrupts only last 1 clock cycle, clear any active interrupt.
            RX_INTR                    <= '0';

            -- When Read and Write FIFO addresses are equal, FIFO is empty.
            if RX_FIFO_RD_ADDR = RX_FIFO_WR_ADDR then
                RX_EMPTY_V             := '1';
            else
                RX_EMPTY_V             := '0';
            end if;

            -- When Write address is 1 behind the read address, FIFO is full.
            if RX_FIFO_WR_ADDR = RX_FIFO_RD_ADDR-1 then
                RX_FULL_V              := '1';
            else
                RX_FULL_V              := '0';
            end if;

            -- If CPU requests to read data, clear the DATA_READY flag.
            --
            if CS = '1' and RDEN = '1' and ADDR = "00" and RX_DATA_READY = '1' then
                RX_DATA_READY          <= '0';
            end if;

            -- If fifo enabled and RX_DATA register is empty, pop the next byte off the stack for the CPU to read.
            --
            if RX_ENABLE_FIFO = '1' and RX_DATA_READY = '0' and RX_EMPTY_V ='0' then
                RX_DATA                <= RX_FIFO( to_integer(RX_FIFO_RD_ADDR) );
                RX_FIFO_RD_ADDR        <= RX_FIFO_RD_ADDR + 1;
                RX_DATA_READY          <= '1';
            end if;

            case RX_STATE is
                when idle =>
                    if RXD_SYNC='0' then
                        RX_STATE       <= start;
                    end if;
                when start =>
                    if RX_CLOCK='1' then
                        if RXD_SYNC='0' then
                            RX_BUFFER  <= "100000000"; -- Set marker bit.
                            RX_STATE   <= bits;
                        else
                            RX_STATE   <= idle;
                        end if;
                    end if;
                when bits =>
                    if RX_CLOCK='1' then
                        RX_BUFFER      <= RXD_SYNC & RX_BUFFER(8 downto 1);
                    end if;
                    if RX_BUFFER(0)='1' then    -- Marker bit has reached bit 0
                        RX_STATE       <= stop;
                    end if;
                when stop =>
                    if RX_CLOCK='1' then
                        if RXD_SYNC='1' then -- valid stop bit?

                            -- If fifo enabled and space available, write otherwise discard.
                            if RX_ENABLE_FIFO = '1' then
                                if RX_FULL_V = '0' then
                                    RX_FIFO(to_integer(RX_FIFO_WR_ADDR)) <= RX_BUFFER(8 downto 1);
                                    RX_FIFO_WR_ADDR <= RX_FIFO_WR_ADDR + 1;
                                else
                                    RX_OVERRUN      <= '1';
                                end if;

                                -- Interrupt if first byte or buffer becoming full.
                                if (RX_EMPTY_V = '1' and RX_DATA_READY = '0') or RX_FIFO_WR_ADDR = RX_FIFO_RD_ADDR - 2 then
                                    RX_INTR         <= '1';
                                end if;
                            else
                                if RX_DATA_READY = '0' then
                                    RX_DATA         <= RX_BUFFER(8 downto 1);
                                    RX_DATA_READY   <= '1';
                                else
                                    RX_OVERRUN      <= '1';
                                end if;

                                -- Always interrupt if fifo disabled.
                                RX_INTR             <= '1';
                            end if;
                        end if;
                        RX_STATE       <= idle;
                    end if;
                when others =>
                    RX_STATE           <= idle;
            end case;
        end if;

        -- Put variables onto external signals.
        RX_FIFO_EMPTY                  <= RX_EMPTY_V;
        RX_FIFO_FULL                   <= RX_FULL_V;

        -- Put internal interrupt status onto bus.
        RXINTR                         <= RX_INTR;
    end process;

    -- Process to read data from the receive buffer/fifo when selected.
    process(clk, RX_RESET, RX_ENABLE)
    begin
        if RX_RESET = '1' then

        elsif RX_ENABLE = '1' and rising_edge(clk) then

        end if;
    end process;


    -- Data Tx
    -- Similarly to the Rx routine, we use a shift register larger than the word,
    -- which also includes a marker bit.  This time the marker bit is a zero, and when
    -- the zero reaches bit 8, we know we've transmitted the entire word plus one stop bit.
    process(clk,TX_RESET,TX_STATE,TX_FIFO_RD_ADDR,TX_FIFO_WR_ADDR,TX_ENABLE,TX_INTR)
        variable TX_FULL_V    : std_logic;
        variable TX_EMPTY_V   : std_logic;
    begin
        if TX_FIFO_RD_ADDR=TX_FIFO_WR_ADDR then
            TX_EMPTY_V  := '1';
        else
            TX_EMPTY_V  := '0';
        end if;

        if TX_FIFO_WR_ADDR = TX_FIFO_RD_ADDR-1 then
            TX_FULL_V   := '1';
        else
            TX_FULL_V   := '0';
        end if;

        if TX_RESET='1' then
            TX_STATE                   <= idle;
            TX_BUSY                    <= '0';
            TX_DATA_LOADED             <= '0';
            TXD                        <= '1';
            TX_INTR                    <= '0';
            TX_OVERRUN                 <= '0';
            TX_FIFO_WR_ADDR            <= (others => '0');
            TX_FIFO_RD_ADDR            <= (others => '0');
            TX_FIFO_EMPTY              <= '1';
            TX_FIFO_FULL               <= '0';

        elsif TX_ENABLE = '1' and rising_edge(clk) then

            TX_INTR    <= '0';

            -- If CPU writes data, load into FIFO or direct into TX Data register.
            --
            if CS = '1' and WREN = '1' and ADDR = "00" then
                -- Store data in FIFO if enabled and not full.
                --
                if TX_ENABLE_FIFO = '1' then
                    if TX_FULL_V = '0' then
                        TX_FIFO(to_integer(TX_FIFO_WR_ADDR)) <= DATA_IN(7 downto 0);
                        TX_FIFO_WR_ADDR<= TX_FIFO_WR_ADDR + 1;
                    else
                        TX_OVERRUN     <= '1';
                    end if;
                else
                    -- Else load TX Data register with data.
                    if TX_DATA_LOADED = '0' then
                        TX_DATA        <= DATA_IN(7 downto 0);
                        TX_DATA_LOADED <= '1';
                    else
                        TX_OVERRUN     <= '1';
                    end if;
                end if;
            end if;

            -- If FIFO enabled, pop the next byte into the TX holding register.
            if TX_ENABLE_FIFO = '1' and TX_DATA_LOADED = '0' and TX_EMPTY_V = '0' then
                TX_DATA                <= TX_FIFO(to_integer(TX_FIFO_RD_ADDR)); 
                TX_FIFO_RD_ADDR        <= TX_FIFO_RD_ADDR + 1;
                TX_DATA_LOADED         <= '1';
            end if;

            -- TX state machine, serialise the TX buffer.
            case TX_STATE is
                when idle =>
                    -- If data loaded into the TX holding register and we are at idle (ie last byte transmitted),
                    -- load into the transmit buffer and commence transmission.
                    --
                    if TX_DATA_LOADED = '1' then
                        TX_BUFFER      <="0111111111" & TX_DATA;    -- marker bit + data
                        TX_STATE       <=bits;
                        TX_BUSY        <='1';
                        TXD            <='0';                       -- Start bit
                        TX_DATA_LOADED <= '0';
                    end if;
                when bits =>
                    if TX_CLOCK='1' then
                        txd            <= TX_BUFFER(0);
                        TX_BUFFER      <= '0' & TX_BUFFER(17 downto 1);

                        if TX_BUFFER(8) = '0' then                  -- Marker bit has reached bit 8
                            TX_STATE   <= idle;
                            TX_BUSY    <= '0';

                            -- Interrupt if there is no data loaded into holding register, either from fifo or direct.
                            if TX_DATA_LOADED = '0' then
                                TX_INTR<= '1';
                            end if;
                        end if;
                    end if;
                when others =>
                    TX_STATE           <=idle;
            end case;
        end if;

        -- Put variables onto external signals.
        TX_FIFO_EMPTY                  <= TX_EMPTY_V;
        TX_FIFO_FULL                   <= TX_FULL_V;

        -- Put internal interrupt status onto bus.
        TXINTR                         <= TX_INTR;
    end process;

    -- Process to pack the data and status onto a buffer ready to be read by the CPU.
    --
    process(ADDR, RX_FIFO_EMPTY, RX_FIFO_FULL, RX_DATA_READY, RX_OVERRUN, RX_INTR, RX_ENABLE_FIFO, RX_ENABLE, RX_RESET,
            TX_FIFO_EMPTY, TX_FIFO_FULL, TX_BUSY, TX_DATA_LOADED, TX_OVERRUN, TX_INTR, TX_ENABLE_FIFO, TX_ENABLE, TX_RESET, 
            TX_CLOCK_DIVISOR, RX_CLOCK_DIVISOR, RX_DATA, RX_FIFO_RD_ADDR, RX_FIFO_WR_ADDR, TX_FIFO_RD_ADDR, TX_FIFO_WR_ADDR)
    begin
        case ADDR is
            when "00" =>
                DATA_OUT                 <= X"000000" & RX_DATA;

            -- Status.
            when "01" =>
                DATA_OUT                 <= (others => '0');
                DATA_OUT(0)              <= RX_FIFO_EMPTY;      -- RX Fifo empty = 1
                DATA_OUT(1)              <= RX_FIFO_FULL;       -- RX Fifo full = 1
                DATA_OUT(2)              <= RX_DATA_READY;      -- RX Byte received in holding register = 1
                DATA_OUT(3)              <= RX_OVERRUN;         -- RX received next data before last was read = 1
                DATA_OUT(4)              <= RX_INTR;            -- RX Interrupt = 1
                DATA_OUT(5)              <= RX_ENABLE_FIFO;     -- RX Fifo enabled = 1
                DATA_OUT(6)              <= RX_ENABLE;          -- RX enabled = 1
                DATA_OUT(7)              <= RX_RESET;           -- RX is in reset = 1
                -- TX Shadow copy, non invasive.
                DATA_OUT(16+0)           <= TX_FIFO_EMPTY;      -- TX Idle = 1
                DATA_OUT(16+1)           <= TX_FIFO_FULL;       -- TX Fifo full = 1
                DATA_OUT(16+2)           <= TX_BUSY;            -- TX Busy serialising = 1
                DATA_OUT(16+3)           <= TX_DATA_LOADED;     -- TX data loaded into holding register = 1
                DATA_OUT(16+4)           <= TX_OVERRUN;         -- TX written to when last byte not sent or fifo full.
                DATA_OUT(16+5)           <= TX_INTR;            -- TX Interrupt = 1
                DATA_OUT(16+6)           <= TX_ENABLE_FIFO;     -- TX Fifo enabled = 1
                DATA_OUT(16+7)           <= TX_ENABLE;          -- TX enabled = 1
                DATA_OUT(16+8)           <= TX_RESET;           -- TX is in reset = 1

            -- FIFO Status.
            when "10" =>
                DATA_OUT                 <= (others => '0');
                DATA_OUT(   RX_FIFO_BIT_DEPTH-1 downto  0) <= std_logic_vector(RX_FIFO_WR_ADDR - RX_FIFO_RD_ADDR);
                DATA_OUT(16+TX_FIFO_BIT_DEPTH-1 downto 16) <= std_logic_vector(TX_FIFO_WR_ADDR - TX_FIFO_RD_ADDR);

            -- Baud Rate Generator setting.
            when "11" =>
                DATA_OUT                 <= std_logic_vector(TX_CLOCK_DIVISOR & RX_CLOCK_DIVISOR);
        end case;
    end process;

    -- Write process. Accept data from the CPU and program the unit accordingly.
    process(CLK,RESET)
    begin
        if RESET='1' then
            RX_CLOCK_DIVISOR             <= X"043D";            -- Default 115200 assuming 100MHz clock.
            TX_CLOCK_DIVISOR             <= X"043D";
            RX_ENABLE                    <= '1';
            TX_ENABLE                    <= '1';
            RX_ENABLE_FIFO               <= '1';
            TX_ENABLE_FIFO               <= '1';
            RX_RESET                     <= '1';
            TX_RESET                     <= '1';

        elsif rising_edge(CLK) then
            RX_RESET                     <= '0';
            TX_RESET                     <= '0';
            if CS = '1' and WREN = '1' then
                case ADDR is
                    -- Data,  written direct to fifo or TX unit.
                    when "00" =>

                    -- RX/TX Control
                    when "01" => -- RX CTL
                        RX_ENABLE        <= DATA_IN(0);
                        RX_ENABLE_FIFO   <= DATA_IN(1);
                        RX_RESET         <= DATA_IN(2);
                        --
                        TX_ENABLE        <= DATA_IN(16+0);
                        TX_ENABLE_FIFO   <= DATA_IN(16+1);
                        TX_RESET         <= DATA_IN(16+2);

                    -- Unused
                    when "10" =>

                    -- Baud Rate Generate setup.
                    when "11" =>
                        RX_CLOCK_DIVISOR <= unsigned(DATA_IN(15 downto 0));
                        TX_CLOCK_DIVISOR <= unsigned(DATA_IN(31 downto 16));
                        RX_RESET         <= '1';
                        TX_RESET         <= '1';
                end case;
            end if;
        end if;
    end process;

end architecture;
