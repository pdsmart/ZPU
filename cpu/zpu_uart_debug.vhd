---------------------------------------------------------------------------------------------------------
--
-- Name:            zpu_uart_debug.vhd
-- Created:         January 2019
-- Author(s):       Philip Smart
-- Description:     An extension of the simplistic UART Tx, still fixed at 8N1 with configurable baud rate
--                  but adding a debug serialisaztion FSM for output of ZPU runtime data.
-- Credits:         Originally using the simplistic UART as a guide, which was written by the following
--                  authors:-
--                  Philippe Carton, philippe.carton2 libertysurf.fr
--                  Juan Pablo Daniel Borgna, jpdborgna gmail.com
--                  Salvador E. Tropea, salvador inti.gob.ar
-- Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
--
-- History:         January 2019  - Initial module written using the simplistic UART as a guide but
--                                  adding cache and debug serialisation FSM.
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

-- Based on the simplistic UART, handles 8N1 RS232 Rx/Tx with independent programmable baud rate and selectable FIFO buffers.
entity zpu_uart_debug is
    generic (
        TX_FIFO_BIT_DEPTH     : integer := DEBUG_MAX_TX_FIFO_BITS;
        DBG_FIFO_BIT_DEPTH    : integer := DEBUG_MAX_FIFO_BITS;
		CLK_FREQ              : integer := 100000000;
        TX_BAUD_RATE          : integer := DEBUG_TX_BAUD_RATE                   -- Default baud rate
    );
    port (
        -- CPU Interface
        CLK                   : in  std_logic;                                  -- memory master clock
        RESET                 : in  std_logic;                                  -- high active sync reset
        DEBUG_DATA            : zpu_dbg_t;
        CS                    : in  std_logic;                                  -- Chip Select.
        READY                 : out std_logic;                                  -- Debug processor ready to process new command.

        -- Serial data
        TXD                   : out std_logic
    );
end zpu_uart_debug;

architecture rtl of zpu_uart_debug is

    type DebugStates is 
    (
        ST_IDLE,
        ST_START,
        ST_ADD_SEPERATOR,
        ST_ADD_SPACE,
        ST_PRECR,
        ST_WRITE,
        ST_WRITEHEX,
        ST_WRITEBIN,
        ST_SPLITSPACE,
        ST_POSTSPACE,
        ST_POSTCRLF,
        ST_POSTLF,
        ST_END
    );

    signal SM_STATE               :  DebugStates;
    signal SM_BITCNT              :  integer range 0 to 7;
    signal SM_BYTECNT             :  integer;
    signal SM_WORDCNT             :  integer range 0 to 4;
    signal SM_NIBBLECNT           :  std_logic;
    signal SM_ADD_SEPERATOR       :  std_logic;
    signal SM_ADD_SPACE           :  std_logic;
    signal SM_SPLIT_DATA          :  std_logic_vector(1 downto 0);

    type TXSTATES is (idle, bits);
    signal TX_STATE               :  TXSTATES := idle;
    signal TX_BUFFER              :  std_logic_vector(17 downto 0);                   -- Transmit serialisation buffer.
    signal TX_DATA                :  std_logic_vector(7 downto 0);                    -- Transmit holding register.
    signal TX_DATA_LOADED         :  std_logic;                                       -- Data loaded into transmit buffer.
    signal TX_COUNTER             :  unsigned(15 downto 0);                           -- TX Clock generator counter.
    signal TX_CLOCK               :  std_logic;                                       -- TX Clock.
    signal TX_LOAD                :  std_logic;                                       -- Load byte into TX fifo.
    signal TX_FIFO_FULL           :  std_logic;                                       -- TX Fifo is full = 1.
    signal TX_WRITE_DATA          :  std_logic_vector(7  downto 0);                   -- write data
    signal SM_DATA_IN             :  std_logic_vector(63 downto 0);                   -- Buffered input data.
    signal DBGREC                 :  zpu_dbg_t;
    
    type ZPU_DBG_MEM_T is array (natural range 0 to ((2**DBG_FIFO_BIT_DEPTH)-1)) of zpu_dbg_t;
    attribute ramstyle            :  string;
    signal DBG_FIFO               :  ZPU_DBG_MEM_T;
    attribute ramstyle of DBG_FIFO:  signal is "M9K";
    signal DBG_FIFO_WR_ADDR       :  unsigned(DBG_FIFO_BIT_DEPTH-1 downto 0);
    signal DBG_FIFO_RD_ADDR       :  unsigned(DBG_FIFO_BIT_DEPTH-1 downto 0);

    -- FIFO buffers.
    --type TX_MEM_T is array (natural range 0 to ((2**TX_FIFO_BIT_DEPTH)-1)) of std_logic_vector(7 downto 0);
    type TX_MEM_T is array (natural range 0 to ((2**TX_FIFO_BIT_DEPTH)-1)) of std_logic_vector(7 downto 0);
    signal TX_FIFO                :  TX_MEM_T;
    -- TX Fifo address pointers.
    --signal TX_FIFO_WR_ADDR        :  unsigned(TX_FIFO_BIT_DEPTH-1 downto 0);
    --signal TX_FIFO_RD_ADDR        :  unsigned(TX_FIFO_BIT_DEPTH-1 downto 0);
    signal TX_FIFO_WR_ADDR        :  unsigned(TX_FIFO_BIT_DEPTH-1 downto 0);
    signal TX_FIFO_RD_ADDR        :  unsigned(TX_FIFO_BIT_DEPTH-1 downto 0);

begin
    -- Debug processor. External input provides a 32bit input which is translated to [1-4]x8bit characters
    -- or [1-4]byte Hex roeds and sent to the debug uart transmitter.
    --
    process(CLK, RESET, DBG_FIFO_RD_ADDR, DBG_FIFO_WR_ADDR)
        variable DBG_FULL_V                           : std_logic;
        variable DBG_EMPTY_V                          : std_logic;
    begin
        if DBG_FIFO_RD_ADDR = DBG_FIFO_WR_ADDR then
            DBG_EMPTY_V                               := '1';
        else
            DBG_EMPTY_V                               := '0';
        end if;

        if DBG_FIFO_WR_ADDR = DBG_FIFO_RD_ADDR-1 then
            DBG_FULL_V                                := '1';
        else
            DBG_FULL_V                                := '0';
        end if;

        -- If we are to fill the last fifo slot, set ready to false so that no more writes occur (if cpu checking).
        --
        if (DBG_FIFO_WR_ADDR - DBG_FIFO_RD_ADDR) > ((2**DBG_FIFO_BIT_DEPTH)-2) then
            READY                                     <= '0';
        elsif (DBG_FIFO_WR_ADDR - DBG_FIFO_RD_ADDR) < ((2**DBG_FIFO_BIT_DEPTH)-2) then
            READY                                     <= '1';
        else
            READY                                     <= '0';
        end if;

        if RESET='1' then
            TX_LOAD                                   <= '0';
            SM_STATE                                  <= ST_IDLE;
            SM_BYTECNT                                <= 0;
            SM_WORDCNT                                <= 0;
            SM_NIBBLECNT                              <= '1';
            SM_ADD_SPACE                              <= '0';
            SM_ADD_SEPERATOR                          <= '0';
            DBG_FIFO_WR_ADDR                          <= (others => '0');
            DBG_FIFO_RD_ADDR                          <= (others => '0');
            READY                                     <= '1';

        elsif rising_edge(CLK) then

            -- If cpu is writing a record to be processed, store in fifo if not full, otherwise wait.
            --
            if CS = '1' then
                -- Store data in FIFO if not full.
                --
                if DBG_FULL_V = '0' then
                    DBG_FIFO(to_integer(DBG_FIFO_WR_ADDR)) <= DEBUG_DATA;
                    DBG_FIFO_WR_ADDR                  <= DBG_FIFO_WR_ADDR + 1;
                end if;
            end if;

            -- When idle, if we have a record in the fifo, extract top record and process.
            --
            if SM_STATE = ST_IDLE and DBG_EMPTY_V = '0' then
                DBGREC                                <= DBG_FIFO(to_integer(DBG_FIFO_RD_ADDR)); 
                DBG_FIFO_RD_ADDR                      <= DBG_FIFO_RD_ADDR + 1;
                SM_STATE                              <= ST_START;
                SM_SPLIT_DATA                         <= "00";
            end if;

            -- Only add characters if the TX Fifo has space, otherwise suspend.
            --
            TX_LOAD                                   <= '0';
            if TX_FIFO_FULL = '0' then
                case SM_STATE is
                    when ST_IDLE =>
    
                    when ST_START =>
                        if SM_ADD_SEPERATOR = '1' then
                            SM_STATE                      <= ST_ADD_SEPERATOR;
                            SM_ADD_SEPERATOR              <= '0';
                        elsif SM_ADD_SPACE = '1' then
                            SM_STATE                      <= ST_ADD_SPACE;
                            SM_ADD_SPACE                  <= '0';
                        elsif DBGREC.FMT_PRE_SPACE = '1' then
                            SM_STATE                      <= ST_ADD_SPACE;
                            DBGREC.FMT_PRE_SPACE          <= '0';
                        elsif DBGREC.FMT_PRE_CR = '1' then
                            SM_STATE                      <= ST_PRECR;
                            DBGREC.FMT_PRE_CR             <= '0';
                        elsif DBGREC.WRITE_PC = '1' then
                            DBGREC.WRITE_PC               <= '0';
                            SM_BYTECNT                    <= 4;
                            SM_DATA_IN(63 downto 32)      <= std_logic_vector(to_unsigned(to_integer(unsigned(DBGREC.PC)), 32));
                            SM_ADD_SPACE                  <= '1';
                            SM_STATE                      <= ST_WRITEHEX;
                        elsif DBGREC.WRITE_SP = '1' then
                            DBGREC.WRITE_SP               <= '0';
                            SM_BYTECNT                    <= 4;
                            SM_DATA_IN(63 downto 32)      <= std_logic_vector(to_unsigned(to_integer(unsigned(DBGREC.SP)), 30)) & "00";
                            SM_ADD_SPACE                  <= '1';
                            SM_STATE                      <= ST_WRITEHEX;
                        elsif DBGREC.WRITE_STACK_TOS = '1' then
                            DBGREC.WRITE_STACK_TOS        <= '0';
                            SM_BYTECNT                    <= 4;
                            SM_DATA_IN(63 downto 32)      <= DBGREC.STACK_TOS;
                            SM_ADD_SPACE                  <= '1';
                            SM_STATE                      <= ST_WRITEHEX;
                        elsif DBGREC.WRITE_STACK_NOS = '1' then
                            DBGREC.WRITE_STACK_NOS        <= '0';
                            SM_BYTECNT                    <= 4;
                            SM_DATA_IN(63 downto 32)      <= DBGREC.STACK_NOS;
                            SM_ADD_SPACE                  <= '1';
                            SM_STATE                      <= ST_WRITEHEX;
                        elsif DBGREC.WRITE_OPCODE = '1' then
                            DBGREC.WRITE_OPCODE           <= '0';
                            SM_BYTECNT                    <= 1;
                            SM_DATA_IN(63 downto 56)      <= DBGREC.OPCODE;
                            SM_ADD_SEPERATOR              <= '1';
                            SM_STATE                      <= ST_WRITEHEX;
                        elsif DBGREC.WRITE_DECODED_OPCODE = '1' then
                            DBGREC.WRITE_DECODED_OPCODE   <= '0';
                            SM_BYTECNT                    <= 1;
                            SM_DATA_IN(63 downto 56)      <= "00" & DBGREC.DECODED_OPCODE;
                            SM_ADD_SPACE                  <= '1';
                            SM_STATE                      <= ST_WRITEHEX;
                        elsif DBGREC.FMT_SPLIT_DATA /= "00" then
                            SM_SPLIT_DATA                 <= DBGREC.FMT_SPLIT_DATA;
                            DBGREC.FMT_SPLIT_DATA         <= "00";
                        elsif DBGREC.WRITE_DATA = '1' then
                            DBGREC.WRITE_DATA             <= '0';
                            SM_BITCNT                     <= 7;
                            SM_BYTECNT                    <= to_integer(unsigned(DBGREC.DATA_BYTECNT)) + 1;
                            SM_WORDCNT                    <= 0;
                            SM_DATA_IN                    <= DBGREC.DATA;
                            if DBGREC.FMT_DATA_PRTMODE = "10" then
                                SM_STATE                  <= ST_WRITEBIN;
                            elsif DBGREC.FMT_DATA_PRTMODE = "01" then
                                SM_STATE                  <= ST_WRITEHEX;
                            else
                                SM_STATE                  <= ST_WRITE;
                            end if;
                        elsif DBGREC.WRITE_DATA2 = '1' then
                            DBGREC.WRITE_DATA2            <= '0';
                            SM_BYTECNT                    <= to_integer(unsigned(DBGREC.DATA2_BYTECNT)) + 1;
                            SM_BITCNT                     <= 7;
                            SM_WORDCNT                    <= 0;
                            SM_DATA_IN                    <= DBGREC.DATA2;
                            if DBGREC.FMT_DATA_PRTMODE = "10" then
                                SM_STATE                  <= ST_WRITEBIN;
                            elsif DBGREC.FMT_DATA_PRTMODE = "01" then
                                SM_STATE                  <= ST_WRITEHEX;
                            else
                                SM_STATE                  <= ST_WRITE;
                            end if;
                        elsif DBGREC.WRITE_DATA3 = '1' then
                            DBGREC.WRITE_DATA3            <= '0';
                            SM_BYTECNT                    <= to_integer(unsigned(DBGREC.DATA3_BYTECNT)) + 1;
                            SM_BITCNT                     <= 7;
                            SM_WORDCNT                    <= 0;
                            SM_DATA_IN                    <= DBGREC.DATA3;
                            if DBGREC.FMT_DATA_PRTMODE = "10" then
                                SM_STATE                  <= ST_WRITEBIN;
                            elsif DBGREC.FMT_DATA_PRTMODE = "01" then
                                SM_STATE                  <= ST_WRITEHEX;
                            else
                                SM_STATE                  <= ST_WRITE;
                            end if;
                        elsif DBGREC.WRITE_DATA4 = '1' then
                            DBGREC.WRITE_DATA4            <= '0';
                            SM_BYTECNT                    <= to_integer(unsigned(DBGREC.DATA4_BYTECNT)) + 1;
                            SM_BITCNT                     <= 7;
                            SM_WORDCNT                    <= 0;
                            SM_DATA_IN                    <= DBGREC.DATA4;
                            if DBGREC.FMT_DATA_PRTMODE = "10" then
                                SM_STATE                  <= ST_WRITEBIN;
                            elsif DBGREC.FMT_DATA_PRTMODE = "01" then
                                SM_STATE                  <= ST_WRITEHEX;
                            else
                                SM_STATE                  <= ST_WRITE;
                            end if;
                        else
                            SM_STATE                      <= ST_END;
                        end if;
    
                    when ST_ADD_SPACE =>
                        TX_WRITE_DATA(7 downto 0)         <= X"20";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_START;
    
                    when ST_ADD_SEPERATOR =>
                        TX_WRITE_DATA(7 downto 0)         <= X"2E";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_START;
    
                    when ST_PRECR =>
                        TX_WRITE_DATA(7 downto 0)         <= X"0D";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_START;
    
                    when ST_WRITE =>
                        if SM_BYTECNT > 0 then
                            TX_WRITE_DATA(7 downto 0)     <= SM_DATA_IN(63 downto 56);
                            TX_LOAD                       <= '1';
                            SM_DATA_IN(63 downto 8)       <= SM_DATA_IN(55 downto 0);
                            SM_BYTECNT                    <= SM_BYTECNT - 1;
                        else
                            SM_STATE                      <= ST_START;
                        end if;
    
                    when ST_WRITEHEX =>
                        if SM_BYTECNT > 0 then
                            if unsigned(SM_DATA_IN(63 downto 60)) < 10 then
                                TX_WRITE_DATA(7 downto 0) <= std_logic_vector(unsigned(SM_DATA_IN(63 downto 60)) + X"30");
                            else
                                TX_WRITE_DATA(7 downto 0) <= std_logic_vector(unsigned(SM_DATA_IN(63 downto 60)) + X"57");
                            end if;
                            TX_LOAD                       <= '1';
                            SM_DATA_IN(63 downto 4)       <= SM_DATA_IN(59 downto 0);
                            if SM_NIBBLECNT = '0' then
                                SM_BYTECNT                <= SM_BYTECNT - 1;
                                if SM_SPLIT_DATA = "01" and SM_WORDCNT = 0 then
                                    SM_STATE              <= ST_SPLITSPACE;
                                    SM_WORDCNT            <= 0;
                                elsif SM_SPLIT_DATA = "10" and SM_WORDCNT = 1 then
                                    SM_STATE              <= ST_SPLITSPACE;
                                    SM_WORDCNT            <= 0;
                                elsif SM_SPLIT_DATA = "11" and SM_WORDCNT > 2 then
                                    SM_STATE              <= ST_SPLITSPACE;
                                    SM_WORDCNT            <= 0;
                                else
                                    SM_WORDCNT            <= SM_WORDCNT + 1;
                                end if;
                            end if;
                            SM_NIBBLECNT                  <= not SM_NIBBLECNT;
                        else
                            SM_STATE                      <= ST_START;
                        end if;

                    when ST_WRITEBIN =>
                        if SM_BYTECNT > 0 then
                            if SM_DATA_IN(63) = '1' then
                                TX_WRITE_DATA(7 downto 0) <= X"31";
                            else
                                TX_WRITE_DATA(7 downto 0) <= X"30";
                            end if;
                            TX_LOAD                       <= '1';
                            SM_DATA_IN(63 downto 1)       <= SM_DATA_IN(62 downto 0);
                            if SM_BITCNT > 0 then
                                SM_BITCNT                 <= SM_BITCNT-1;
                            else
                                SM_BITCNT                 <= 7;
                                SM_BYTECNT                <= SM_BYTECNT - 1;
                            end if;
                        else
                            SM_STATE                      <= ST_START;
                        end if;

                    when ST_SPLITSPACE =>
                        TX_WRITE_DATA(7 downto 0)         <= X"20";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_WRITEHEX;
    
                    when ST_POSTSPACE =>
                        TX_WRITE_DATA(7 downto 0)         <= X"20";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_END;
    
                    when ST_POSTCRLF =>
                        TX_WRITE_DATA(7 downto 0)         <= X"0D";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_POSTLF;
    
                    when ST_POSTLF =>
                        TX_WRITE_DATA(7 downto 0)         <= X"0A";
                        TX_LOAD                           <= '1';
                        SM_STATE                          <= ST_END;
    
                    when ST_END =>
                        if DBGREC.FMT_POST_SPACE = '1' then
                            SM_STATE                      <= ST_POSTSPACE;
                            DBGREC.FMT_POST_SPACE         <= '0';
                        elsif DBGREC.FMT_POST_CRLF = '1' then
                            SM_STATE                      <= ST_POSTCRLF;
                            DBGREC.FMT_POST_CRLF          <= '0';
                        else
                            SM_STATE                      <= ST_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- Tx Clock generation
    -- Very simple - the counter is reset when either it reaches zero or
    -- the Tx is idle, and counts down once per system clock tick.
    process(CLK, RESET)
    begin
        if RESET='1' then
            TX_CLOCK                   <= '0';
            TX_COUNTER                 <= to_unsigned(CLK_FREQ/TX_BAUD_RATE, TX_COUNTER'length); 
        elsif rising_edge(CLK) then
            TX_CLOCK                   <= '0';

            if TX_STATE = idle then
                TX_COUNTER             <= to_unsigned(CLK_FREQ/TX_BAUD_RATE, TX_COUNTER'length);
            else
                TX_COUNTER             <= TX_COUNTER-1;
                if TX_COUNTER = 0 then
                    TX_CLOCK           <= '1';
                    TX_COUNTER         <= to_unsigned(CLK_FREQ/TX_BAUD_RATE, TX_COUNTER'length);
                end if;
            end if;
        end if;
    end process;

    
    -- Data Tx
    -- Similarly to the Rx routine, we use a shift register larger than the word,
    -- which also includes a marker bit.  This time the marker bit is a zero, and when
    -- the zero reaches bit 8, we know we've transmitted the entire word plus one stop bit.
    process(clk,RESET,TX_STATE,TX_FIFO_RD_ADDR,TX_FIFO_WR_ADDR)
        variable TX_FULL_V             : std_logic;
        variable TX_EMPTY_V            : std_logic;
        variable DATA_HEX_LSB          : std_logic_vector(7 downto 0);
        variable DATA_HEX_MSB          : std_logic_vector(7 downto 0);
    begin
        if TX_FIFO_RD_ADDR=TX_FIFO_WR_ADDR then
            TX_EMPTY_V                 := '1';
        else
            TX_EMPTY_V                 := '0';
        end if;

        if TX_FIFO_WR_ADDR = TX_FIFO_RD_ADDR-1 then
            TX_FULL_V                  := '1';
        else
            TX_FULL_V                  := '0';
        end if;

        -- Full is set when we are almost full or an unspecified state and reset when the data in the buffer is 256 bytes less than
        -- maximum.
        if (TX_FIFO_WR_ADDR - TX_FIFO_RD_ADDR) > ((2**TX_FIFO_BIT_DEPTH)-16) then
            TX_FIFO_FULL               <= '1';
        elsif (TX_FIFO_WR_ADDR - TX_FIFO_RD_ADDR) < ((2**TX_FIFO_BIT_DEPTH)-256) then
            TX_FIFO_FULL               <= '0';
        else
            TX_FIFO_FULL               <= '1';
        end if;

        if RESET='1' then
            TX_STATE                   <= idle;
            TX_DATA_LOADED             <= '0';
            TXD                        <= '1';
            TX_FIFO_FULL               <= '0';
            TX_FIFO_WR_ADDR            <= (others => '0');
            TX_FIFO_RD_ADDR            <= (others => '0');

        elsif rising_edge(clk) then

            -- If CPU writes data, load into FIFO.
            --
            if TX_LOAD = '1' then

                -- Store data in FIFO if not full.
                --
                if TX_FULL_V = '0' then
                    TX_FIFO(to_integer(TX_FIFO_WR_ADDR)) <= TX_WRITE_DATA(7 downto 0);
                    TX_FIFO_WR_ADDR    <= TX_FIFO_WR_ADDR + 1;
                end if;
            end if;

            -- If FIFO enabled, pop the next byte into the TX holding register.
            if TX_DATA_LOADED = '0' and TX_EMPTY_V = '0' then
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
                        TX_BUFFER      <= "0111111111" & TX_DATA;    -- marker bit + data
                        TX_STATE       <= bits;
                        TXD            <= '0';                       -- Start bit
                        TX_DATA_LOADED <= '0';
                    end if;
                when bits =>
                    if TX_CLOCK='1' then
                        TXD            <= TX_BUFFER(0);
                        TX_BUFFER      <= '0' & TX_BUFFER(17 downto 1);

                        if TX_BUFFER(8) = '0' then                  -- Marker bit has reached bit 8
                            TX_STATE   <= idle;
                        end if;
                    end if;
                when others =>
                    TX_STATE           <= idle;
            end case;
        end if;
    end process;
end architecture;
