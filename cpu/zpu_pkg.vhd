-- ZPU
--
-- Copyright 2004-2008 oharboe - �yvind Harboe - oyvind.harboe@zylin.com
-- Copyright 2018-2019 psmart  - Philip Smart 
-- 
-- The FreeBSD license
-- 
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above
--    copyright notice, this list of conditions and the following
--    disclaimer in the documentation and/or other materials
--    provided with the distribution.
-- 
-- THIS SOFTWARE IS PROVIDED BY THE ZPU PROJECT ``AS IS'' AND ANY
-- EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
-- PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
-- ZPU PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
-- INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
-- STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-- 
-- The views and conclusions contained in the software and documentation
-- are those of the authors and should not be interpreted as representing
-- official policies, either expressed or implied, of the ZPU Project.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package zpu_pkg is

    -- Constants common to all ZPU models source code.
    constant Generate_Trace           :     boolean          := false;                               -- generate trace output or not.
    constant wordPower                :     integer          := 5;                                   -- The number of bits in a word, defined as 2^wordPower).
    constant DontCareValue            :     std_logic        := 'X';                                 -- during simulation, set this to '0' to get matching trace.txt 
    constant byteBits                 :     integer          := wordPower-3;                         -- # of bits in a word that addresses bytes
    constant wordSize                 :     integer          := 2**wordPower;
    constant wordBytes                :     integer          := wordSize/8;
    constant minAddrBit               :     integer          := byteBits;
    constant WB_ACTIVE                :     integer          := 1;                                   -- Set to 1 if the wishbone interface is active to divide the address space in two, lower = direct access, upper = wishbone.
    constant maxAddrBit               :     integer          := 24 + WB_ACTIVE;                      -- Maximum address limit in bits.
    constant maxAddrSize              :     integer          := (2**maxAddrBit);                     -- Maximum address space size in bytes.
    constant maxIOBit                 :     integer          := maxAddrBit - WB_ACTIVE - 4;          -- Upper bit (to define range) of IO space in top section of address space.
--  constant maxMemBit                :     integer          := 16;                                  -- Non-EVO: Maximum memory bit, should be equal to maxAddrBit-1, Memory and IO each have 1/2 address space.
    constant ioBit                    :     integer          := maxAddrBit - 1;                      -- Non-EVO: MSB is used to differentiate IO and memory.


    constant ADDR_32BIT_SIZE          :     integer          := maxAddrBit - minAddrBit;             -- Bits in the address bus relevant for 32bit access.
    constant WB_SELECT_BIT            :     integer          := maxAddrBit - 1;                      -- Bit which divides the wishbone interface from normal memory space.

    -- Ranges used throughout the SOC/ZPU source.
    subtype ADDR_BIT_RANGE            is natural range maxAddrBit-1    downto 0;                     -- Full address range - 1 byte aligned
    subtype ADDR_16BIT_RANGE          is natural range maxAddrBit-1    downto 1;                     -- Full address range - 2 bytes (16bit) aligned 
    subtype ADDR_32BIT_RANGE          is natural range maxAddrBit-1    downto minAddrBit;            -- Full address range - 4 bytes (32bit) aligned
    subtype ADDR_64BIT_RANGE          is natural range maxAddrBit-1    downto minAddrBit+1;          -- Full address range - 8 bytes (64bit) aligned
--    subtype ADDR_MEM_32BIT_RANGE      is natural range maxAddrBit-1    downto minAddrBit;            -- Non-EVO: Memory range.
    subtype ADDR_IOBIT_RANGE          is natural range ioBit           downto minAddrBit;            -- Non-EVO: IO range.
    subtype WORD_32BIT_RANGE          is natural range wordSize-1      downto 0;                     -- Number of bits in a word (normally 32 for this CPU).
    subtype WORD_4BYTE_RANGE          is natural range wordBytes-1     downto 0;                     -- Bits needed to represent wordSize in bytes (normally 4 for 32bits).
    subtype BYTE_RANGE                is natural range 7               downto 0;                     -- Number of bits in a byte.

    -- Evo specific options.
    --
    constant EVO_USE_INSN_BUS         :     boolean          := true;                                -- Use a seperate instruction bus to connect to the BRAM memory. All other operations go over the normal bus.
    constant EVO_USE_HW_BYTE_WRITE    :     boolean          := true;                                -- Implement hardware writing of bytes, reads are always 32bit and aligned.
    constant EVO_USE_HW_WORD_WRITE    :     boolean          := true;                                -- Implement hardware writing of 16bit words,  reads are always 32bit and aligned.
    constant EVO_USE_WB_BUS           :     boolean          := true;                                -- Implement the wishbone interface in addition to the standard direct interface. NB: Change WB_ACTIVE to 1 above if enabling.
    constant EVO_IMPL_RAM             :     boolean          := true;                                -- Implement application RAM, seperate to the BRAM using BRAM. The main BRAM would then be just for initial boot up.

    -- Debug options.
    --
    constant DEBUG_CPU                :     boolean          := false;                               -- Enable CPU debugging output.
    constant DEBUG_LEVEL              :     integer          := 1;                                   -- Level of debugging output. 0 = Basic, such as Breakpoint, 1 =+ Executing Instructions, 2 =+ L1 Cache contents, 3 =+ L2 Cache contents, 4 =+ Memory contents, 5=+ 4Everything else.
    constant DEBUG_MAX_TX_FIFO_BITS   :     integer          := 12;                                  -- Size of UART TX Fifo for debug output.
    constant DEBUG_MAX_FIFO_BITS      :     integer          := 3;                                   -- Size of debug output data records fifo.
    constant DEBUG_TX_BAUD_RATE       :     integer          := 115200; --230400;                    -- Baud rate for the debug transmitter.

    ------------------------------------------------------------ 
    -- components
    ------------------------------------------------------------ 
    component zpu_core_flex is
        generic (
            IMPL_MULTIPLY             : boolean := true;        -- Self explanatory
            IMPL_COMPARISON_SUB       : boolean := true;        -- Include sub and (U)lessthan(orequal)
            IMPL_EQBRANCH             : boolean := true;        -- Include eqbranch and neqbranch
            IMPL_STOREBH              : boolean := false;       -- Include halfword and byte writes
            IMPL_LOADBH               : boolean := false;       -- Include halfword and byte reads
            IMPL_CALL                 : boolean := true;        -- Include call
            IMPL_SHIFT                : boolean := true;        -- Include lshiftright, ashiftright and ashiftleft
            IMPL_XOR                  : boolean := true;        -- include xor instruction
            CACHE                     : boolean := false;
            CLK_FREQ                  : integer := 100000000;   -- Frequency of the input clock.
            STACK_ADDR                : integer := 0            -- Initial stack address on CPU start.
        );
        port ( 
            clk                       : in  std_logic;
            reset                     : in  std_logic;
            enable                    : in  std_logic := '1'; 
            in_mem_busy               : in  std_logic;
            mem_read                  : in  std_logic_vector(WORD_32BIT_RANGE);
            mem_write                 : out std_logic_vector(WORD_32BIT_RANGE);
            out_mem_addr              : out std_logic_vector(ADDR_BIT_RANGE);
            out_mem_writeEnable       : out std_logic;
            out_mem_bEnable           : out std_logic;
            out_mem_hEnable           : out std_logic;
            out_mem_readEnable        : out std_logic;
          --mem_writeMask        
            interrupt_request         : in  std_logic;
            interrupt_ack             : out std_logic;          -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
            interrupt_done            : out std_logic;          -- Interrupt service routine completed/done.
            break                     : out std_logic;
            debug_txd                 : out std_logic;          -- Debug serial output.
            --
            MEM_A_WRITE_ENABLE        : out std_logic;
            MEM_A_ADDR                : out std_logic_vector(ADDR_32BIT_RANGE);
            MEM_A_WRITE               : out std_logic_vector(WORD_32BIT_RANGE);
            MEM_B_WRITE_ENABLE        : out std_logic;
            MEM_B_ADDR                : out std_logic_vector(ADDR_32BIT_RANGE);
            MEM_B_WRITE               : out std_logic_vector(WORD_32BIT_RANGE);
            MEM_A_READ                : in  std_logic_vector(WORD_32BIT_RANGE);
            MEM_B_READ                : in  std_logic_vector(WORD_32BIT_RANGE)
          );
    end component zpu_core_flex;

    component zpu_core_small is
        generic (
            CLK_FREQ                  : integer := 100000000;   -- Frequency of the input clock.
            STACK_ADDR                : integer := 0            -- Initial stack address on CPU start.
        );
        port (
            clk                       : in  std_logic;
            -- asynchronous reset signal
            areset                    : in  std_logic;
            -- this particular implementation of the ZPU does not
            -- have a clocked enable signal
            enable                    : in  std_logic; 
            in_mem_busy               : in  std_logic; 
            mem_read                  : in  std_logic_vector(WORD_32BIT_RANGE);
            mem_write                 : out std_logic_vector(WORD_32BIT_RANGE);              
            out_mem_addr              : out std_logic_vector(ADDR_BIT_RANGE);
            out_mem_writeEnable       : out std_logic; 
            out_mem_bEnable           : out std_logic;
            out_mem_hEnable           : out std_logic;
            out_mem_readEnable        : out std_logic;
            -- this implementation of the ZPU *always* reads and writes entire
            -- 32 bit words, so mem_writeMask is tied to (others => '1').
            mem_writeMask             : out std_logic_vector(wordBytes-1 downto 0);
            -- Set to one to jump to interrupt vector
            -- The ZPU will communicate with the hardware that caused the
            -- interrupt via memory mapped IO or the interrupt flag can
            -- be cleared automatically
            interrupt_request         : in  std_logic;
            interrupt_ack             : out std_logic;          -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
            interrupt_done            : out std_logic;          -- Interrupt service routine completed/done.        : out std_logic_vector(wordBytes-1 downto 0);
            -- Signal that the break instruction is executed, normally only used
            -- in simulation to stop simulation
            break                     : out std_logic;
            debug_txd                 : out std_logic;          -- Debug serial output.
            --
            MEM_A_WRITE_ENABLE        : out std_logic;
            MEM_A_ADDR                : out std_logic_vector(ADDR_32BIT_RANGE);
            MEM_A_WRITE               : out std_logic_vector(WORD_32BIT_RANGE);
            MEM_B_WRITE_ENABLE        : out std_logic;
            MEM_B_ADDR                : out std_logic_vector(ADDR_32BIT_RANGE);
            MEM_B_WRITE               : out std_logic_vector(WORD_32BIT_RANGE);
            MEM_A_READ                : in  std_logic_vector(WORD_32BIT_RANGE);
            MEM_B_READ                : in  std_logic_vector(WORD_32BIT_RANGE)
        );
    end component zpu_core_small;

    component zpu_core_medium is
        generic (
            CLK_FREQ                  : integer := 100000000;   -- Frequency of the input clock.
            STACK_ADDR                : integer := 0            -- Initial stack address on CPU start.
        );
        port (
            clk                       : in  std_logic;
            areset                    : in  std_logic;
            enable                    : in  std_logic; 
            in_mem_busy               : in  std_logic; 
            mem_read                  : in  std_logic_vector(WORD_32BIT_RANGE);
            mem_write                 : out std_logic_vector(WORD_32BIT_RANGE);
            out_mem_addr              : out std_logic_vector(ADDR_BIT_RANGE);
            out_mem_writeEnable       : out std_logic; 
            out_mem_bEnable           : out std_logic;
            out_mem_hEnable           : out std_logic;
            out_mem_readEnable        : out std_logic;
            mem_writeMask             : out std_logic_vector(WORD_4BYTE_RANGE);
            interrupt_request         : in  std_logic;
            interrupt_ack             : out std_logic;          -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
            interrupt_done            : out std_logic;          -- Interrupt service routine completed/done.        : out std_logic_vector(wordBytes-1 downto 0);
            break                     : out std_logic;
            debug_txd                 : out std_logic           -- Debug serial output.
        );
    end component zpu_core_medium;

    component zpu_core_evo is
        generic (
            -- Optional hardware features to be implemented.
            IMPL_HW_BYTE_WRITE        : boolean := false;       -- Enable use of hardware direct byte write rather than read 32bits-modify 8 bits-write 32bits.
            IMPL_HW_WORD_WRITE        : boolean := false;       -- Enable use of hardware direct byte write rather than read 32bits-modify 16 bits-write 32bits.
            IMPL_OPTIMIZE_IM          : boolean := true;        -- If the instruction cache is enabled, optimise Im instructions to gain speed.
            IMPL_USE_INSN_BUS         : boolean := true;        -- Use a seperate bus to read instruction memory, normally implemented in BRAM.
            IMPL_USE_WB_BUS           : boolean := true;        -- Use the wishbone interface in addition to direct access bus.
            -- Optional instructions to be implemented in hardware:
            IMPL_ASHIFTLEFT           : boolean := true;        -- Arithmetic Shift Left (uses same logic so normally combined with ASHIFTRIGHT and LSHIFTRIGHT).
            IMPL_ASHIFTRIGHT          : boolean := true;        -- Arithmetic Shift Right.
            IMPL_CALL                 : boolean := true;        -- Call to direct address.
            IMPL_CALLPCREL            : boolean := true;        -- Call to indirect address (add offset to program counter).
            IMPL_DIV                  : boolean := true;        -- 32bit signed division.
            IMPL_EQ                   : boolean := true;        -- Equality test.
            IMPL_EXTENDED_INSN        : boolean := true;        -- Extended multibyte instruction set.
            IMPL_FIADD32              : boolean := true;        -- Fixed point Q17.15 addition.
            IMPL_FIDIV32              : boolean := true;        -- Fixed point Q17.15 division.
            IMPL_FIMULT32             : boolean := true;        -- Fixed point Q17.15 multiplication.
            IMPL_LOADB                : boolean := true;        -- Load single byte from memory.
            IMPL_LOADH                : boolean := true;        -- Load half word (16bit) from memory.
            IMPL_LSHIFTRIGHT          : boolean := true;        -- Logical shift right.
            IMPL_MOD                  : boolean := false;       -- 32bit modulo (remainder after division).
            IMPL_MULT                 : boolean := true;        -- 32bit signed multiplication.
            IMPL_NEG                  : boolean := false;       -- Negate value in TOS.
            IMPL_NEQ                  : boolean := true;        -- Not equal test.
            IMPL_POPPCREL             : boolean := true;        -- Pop a value into the Program Counter from a location relative to the Stack Pointer.
            IMPL_PUSHSPADD            : boolean := true;        -- Add a value to the Stack pointer and push it onto the stack.
            IMPL_STOREB               : boolean := true;        -- Store/Write a single byte to memory/IO.
            IMPL_STOREH               : boolean := true;        -- Store/Write a half word (16bit) to memory/IO.
            IMPL_SUB                  : boolean := true;        -- 32bit signed subtract.
            IMPL_XOR                  : boolean := true;        -- Exclusive or of value in TOS.
            -- Size/Control parameters for the optional hardware.
            MAX_INSNRAM_SIZE          : integer := 32768;       -- Maximum size of the optional Instruction BRAM on the INSN Bus.
            MAX_L1CACHE_BITS          : integer := 4;           -- Maximum size in bytes of the Level 1 instruction cache governed by the number of bits, ie. 8 = 256 byte cache.
            MAX_L2CACHE_BITS          : integer := 12;          -- Maximum size in bytes of the Level 2 instruction cache governed by the number of bits, ie. 8 = 256 byte cache.
            MAX_MXCACHE_BITS          : integer := 4;           -- Maximum size of the memory transaction cache governed by the number of bits.
            RESET_ADDR_CPU            : integer := 0;           -- Initial start address of the CPU.
            START_ADDR_MEM            : integer := 0;           -- Start address of program memory.
            STACK_ADDR                : integer := 0;           -- Initial stack address on CPU start.            
            CLK_FREQ                  : integer := 100000000           -- Frequency of the input clock.
        );
        port (
            CLK                       : in  std_logic;
            RESET                     : in  std_logic;
            ENABLE                    : in  std_logic; 
            --
            MEM_BUSY                  : in  std_logic; 
            MEM_DATA_IN               : in  std_logic_vector(WORD_32BIT_RANGE);
            MEM_DATA_OUT              : out std_logic_vector(WORD_32BIT_RANGE);
            MEM_ADDR                  : out std_logic_vector(ADDR_BIT_RANGE);
            MEM_WRITE_ENABLE          : out std_logic; 
            MEM_READ_ENABLE           : out std_logic;
            MEM_WRITE_BYTE            : out std_logic;
            MEM_WRITE_HWORD           : out std_logic;
            -- Instruction memory path
            MEM_BUSY_INSN             : in  std_logic; 
            MEM_DATA_IN_INSN          : in  std_logic_vector(WORD_32BIT_RANGE);
            MEM_ADDR_INSN             : out std_logic_vector(ADDR_BIT_RANGE);
            MEM_READ_ENABLE_INSN      : out std_logic;
            -- Master Wishbone Memory/IO bus interface.
            WB_CLK_I                  : in  std_logic;
            WB_RST_I                  : in  std_logic;
            WB_ACK_I                  : in  std_logic;
            WB_DAT_I                  : in  std_logic_vector(WORD_32BIT_RANGE);
            WB_DAT_O                  : out std_logic_vector(WORD_32BIT_RANGE);
            WB_ADR_O                  : out std_logic_vector(ADDR_BIT_RANGE);
            WB_CYC_O                  : out std_logic;
            WB_STB_O                  : out std_logic;
            WB_CTI_O                  : out std_logic_vector(2 downto 0);
            WB_WE_O                   : out std_logic;
            WB_SEL_O                  : out std_logic_vector(WORD_4BYTE_RANGE);
            WB_HALT_I                 : in  std_logic;
            WB_ERR_I                  : in  std_logic;
            WB_INTA_I                 : in  std_logic;

            -- Set to one to jump to interrupt vector
            -- The ZPU will communicate with the hardware that caused the
            -- interrupt via memory mapped IO or the interrupt flag can
            -- be cleared automatically
            INT_REQ                   : in  std_logic;
            INT_ACK                   : out std_logic;          -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
            INT_DONE                  : out std_logic;          -- Interrupt service routine completed/done.
            -- Break and debug signals.
            BREAK                     : out std_logic;          -- A break instruction encountered.
            CONTINUE                  : in  std_logic;          -- When break activated, processing stops. Setting CONTINUE to logic 1 resumes processing with next instruction.
            DEBUG_TXD                 : out std_logic           -- Debug serial output.        
        );
    end component zpu_core_evo;

    component dpram
        generic (
            init_file                 : string;
            widthad_a                 : natural;
            width_a                   : natural;
            widthad_b                 : natural;
            width_b                   : natural;
            outdata_reg_a             : string := "UNREGISTERED";
            outdata_reg_b             : string := "UNREGISTERED"
        );
        port (
            clock_a                   : in  std_logic  := '1';
            clocken_a                 : in  std_logic  := '1';
            address_a                 : in  std_logic_vector (widthad_a-1 downto 0);
            data_a                    : in  std_logic_vector (width_a-1 downto 0);
            wren_a                    : in  std_logic  := '0';
            q_a                       : out std_logic_vector (width_a-1 downto 0);

            clock_b                   : in  std_logic;
            clocken_b                 : in  std_logic  := '1';
            address_b                 : in  std_logic_vector (widthad_b-1 downto 0);
            data_b                    : in  std_logic_vector (width_b-1 downto 0);
            wren_b                    : in  std_logic  := '0';
            q_b                       : out std_logic_vector (width_b-1 downto 0)
      );
    end component;

    ------------------------------------------------------------ 
    -- constants
    ------------------------------------------------------------ 

    -- opcode decode constants
    constant OpCode_Im                  : std_logic_vector(7 downto 7) := "1";
    constant OpCode_StoreSP             : std_logic_vector(7 downto 5) := "010";
    constant OpCode_LoadSP              : std_logic_vector(7 downto 5) := "011";
    constant OpCode_Emulate             : std_logic_vector(7 downto 5) := "001";
    constant OpCode_AddSP               : std_logic_vector(7 downto 4) := "0001";
    constant OpCode_Short               : std_logic_vector(7 downto 4) := "0000";
    --
    constant OpCode_Break               : std_logic_vector(3 downto 0) := "0000";
    constant OpCode_NA4                 : std_logic_vector(3 downto 0) := "0001";
    constant OpCode_PushSP              : std_logic_vector(3 downto 0) := "0010";
    constant OpCode_NA3                 : std_logic_vector(3 downto 0) := "0011";
    --
    constant OpCode_PopPC               : std_logic_vector(3 downto 0) := "0100";
    constant OpCode_Add                 : std_logic_vector(3 downto 0) := "0101";
    constant OpCode_And                 : std_logic_vector(3 downto 0) := "0110";
    constant OpCode_Or                  : std_logic_vector(3 downto 0) := "0111";
    --
    constant OpCode_Load                : std_logic_vector(3 downto 0) := "1000";
    constant OpCode_Not                 : std_logic_vector(3 downto 0) := "1001";
    constant OpCode_Flip                : std_logic_vector(3 downto 0) := "1010";
    constant OpCode_Nop                 : std_logic_vector(3 downto 0) := "1011";
    --
    constant OpCode_Store               : std_logic_vector(3 downto 0) := "1100";
    constant OpCode_PopSP               : std_logic_vector(3 downto 0) := "1101";
    constant OpCode_NA2                 : std_logic_vector(3 downto 0) := "1110";
    constant OpCode_Extend              : std_logic_vector(3 downto 0) := "1111";
    --
    constant OpCode_Loadh               : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(34, 6));
    constant OpCode_Storeh              : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(35, 6));
    --
    constant OpCode_Lessthan            : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(36, 6));
    constant OpCode_Lessthanorequal     : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(37, 6));
    constant OpCode_Ulessthan           : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(38, 6));
    constant OpCode_Ulessthanorequal    : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(39, 6));
    --
    constant OpCode_Swap                : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(40, 6));
    constant OpCode_Mult                : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(41, 6));
    --
    constant OpCode_Lshiftright         : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(42, 6));
    constant OpCode_Ashiftleft          : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(43, 6));
    constant OpCode_Ashiftright         : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(44, 6));
    constant OpCode_Call                : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(45, 6));
    --
    constant OpCode_Eq                  : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(46, 6));
    constant OpCode_Neq                 : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(47, 6));
    --
    constant OpCode_Neg                 : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(48, 6));
    constant OpCode_Sub                 : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(49, 6));
    constant OpCode_Xor                 : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(50, 6));
    --
    constant OpCode_Loadb               : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(51, 6));
    constant OpCode_Storeb              : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(52, 6));
    --
    constant OpCode_Div                 : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(53, 6));
    constant OpCode_Mod                 : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(54, 6));
    --
    constant OpCode_Eqbranch            : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(55, 6));
    constant OpCode_Neqbranch           : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(56, 6));
    constant OpCode_Poppcrel            : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(57, 6));
    --
    constant OpCode_FiAdd32             : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(58, 6));
    constant OpCode_FiDiv32             : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(59, 6));
    constant OpCode_FiMult32            : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(60, 6));
    --
    constant OpCode_Pushspadd           : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(61, 6));
    constant OpCode_Mult16x16           : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(62, 6));
    constant OpCode_Callpcrel           : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(63, 6));
    --
    -- Extension instructions. 
    constant Opcode_Ex_Fill             : std_logic_vector(7 downto 2) := "000001";
    --
    constant OpCode_Size                : integer                      := 8;
    --

    ------------------------------------------------------------ 
    -- records
    ------------------------------------------------------------ 

    -- Debug structure, currently only for the trace module
    type zpu_dbgo_t is record
        b_inst                          : std_logic;
        opcode                          : unsigned(OpCode_Size-1 downto 0);
        pc                              : unsigned(31 downto 0);
        sp                              : unsigned(31 downto 0);
        stk_a                           : unsigned(31 downto 0);
        stk_b                           : unsigned(31 downto 0);
    end record;
  
    type zpu_dbg_t is record
        FMT_DATA_PRTMODE                : std_logic_vector(1 downto 0);
        FMT_PRE_SPACE                   : std_logic;
        FMT_POST_SPACE                  : std_logic;
        FMT_PRE_CR                      : std_logic;
        FMT_POST_CRLF                   : std_logic;
        FMT_SPLIT_DATA                  : std_logic_vector(1 downto 0);
        DATA_BYTECNT                    : std_logic_vector(2 downto 0);
        DATA2_BYTECNT                   : std_logic_vector(2 downto 0);
        DATA3_BYTECNT                   : std_logic_vector(2 downto 0);
        DATA4_BYTECNT                   : std_logic_vector(2 downto 0);
        WRITE_DATA                      : std_logic;
        WRITE_DATA2                     : std_logic;
        WRITE_DATA3                     : std_logic;
        WRITE_DATA4                     : std_logic;
        WRITE_OPCODE                    : std_logic;
        WRITE_DECODED_OPCODE            : std_logic;
        WRITE_PC                        : std_logic;
        WRITE_SP                        : std_logic;
        WRITE_STACK_TOS                 : std_logic;
        WRITE_STACK_NOS                 : std_logic;
        DATA                            : std_logic_vector(63 downto 0);
        DATA2                           : std_logic_vector(63 downto 0);
        DATA3                           : std_logic_vector(63 downto 0);
        DATA4                           : std_logic_vector(63 downto 0);
        OPCODE                          : std_logic_vector(OpCode_Size-1 downto 0);
        DECODED_OPCODE                  : std_logic_vector(5 downto 0);
        PC                              : std_logic_vector(ADDR_BIT_RANGE);
        SP                              : std_logic_vector(ADDR_32BIT_RANGE);
        STACK_TOS                       : std_logic_vector(WORD_32BIT_RANGE);
        STACK_NOS                       : std_logic_vector(WORD_32BIT_RANGE);
    end record;

    constant ZPU_DBG_T_INIT : zpu_dbg_t := ("00", '0', '0', '0', '0', (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'), (others => '0'));
    constant ZPU_DBG_T_DONTCARE : zpu_dbg_t := ((others => DontCareValue), DontCareValue, DontCareValue, DontCareValue, DontCareValue, (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), DontCareValue, DontCareValue, DontCareValue, DontCareValue, DontCareValue, DontCareValue, DontCareValue, DontCareValue, DontCareValue, DontCareValue, (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue), (others => DontCareValue));
end zpu_pkg;
