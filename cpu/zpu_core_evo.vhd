-- ZPU Evolution
--
-- Copyright 2004-2008 (ZPU Design, Small, Medium)  oharboe - Øyvind Harboe - oyvind.harboe@zylin.com
-- Copyright 2008      (zpuino) alvieboy - Álvaro Lopes - alvieboy@alvie.com
-- Copyright 2013      (zpuflex) Alastair M. Robinson
-- Copyright 2018-2021 (ZPU Evo) Philip Smart
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
--
-- Evo History:
-- ------------
--  181230 v0.1  Initial version created by merging items of the Small, Medium and Flex versions.
--  190328 v0.5  Working with Instruction, Emulation or No Cache with or without seperate instruction
--               bus. Runs numerous tests and output same as the Medium CPU. One small issue is running
--               without an instruction bus and instruction/emulation cache enabled, the DMIPS value is lower
--               than just with instruction bus or emulation bus, seems some clash which reuults in waits states
--               slowing the CPU down.
--  191021 v1.0  First release. All variations tested but more work needed on the SDRAM controller to
--               make use of burst mode in order to populate the L2 cache in fewer cycles.
--               Additional instructions need to be added back in after test and verification, albeit some
--               which are specific to the Sharp Emulator should be skipped.
--               Additional effort needs spending on the Wishbone Error signal to retry the bus transaction,
--               currently it just aborts it which is not ideal.
--  191126 v1.1  Bug fixes. When switching off WishBone the CPU wouldnt run.
--  191215 v1.2  Bug fixes. Removed L2 Cache megacore and replaced with inferred equivalent, fixed hardware
--               byte/h-word write which was always defaulting to read-update-write, fixed L2 timing with
--               external SDRAM, minor tweaks and currently looking at better constraints.
--  191220 v1.21 Changes to Mult, shifting it from a combination assignment to a clocked assignment to improve
--               slack. Small changes made for slack in setup and hold.
--  201229 v1.3  During porting of the CPU to the Sharp MZ series where it acts as a host processor, it was noticed
--               that the ENABLE mechanism, which came from the original ZPU, needs to be more thoroughly tested and enhanced in this design.
--               It is alright disabling the processor unit by setting ENABLE low but the cache is still active and therefore the bus. Thus 
--               a proper bus request/ack mechanism was needed in the memory transaction processor to halt bus operations when requested.
--  210110 v1.4  Reworking the L1 cache to be 64bit wide, allowing for decoding of 8 instructions per loop (2 clock cycles). Bug resolution
--               for the SDRAM cache bug, the L2 cache fetch and store takes 2-3 cycles, once launched it is expected to complete but a PC
--               change could see the target address changing and the fetch from the old location stored into the new.
--  210113 v1.5  Fixed shift operators, a misunderstanding of the requirements led to the wrong design which when activated (ie. hardware
--               options enabled at GCC compile time) failed.
--         

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.zpu_pkg.all;

--------------------------------------------------------------------------------------------------------------------------------------------
-- ZPU Evo Signal Description.
--------------------------------------------------------------------------------------------------------------------------------------------
--
-- Main Memory/IO Bus.
-- -------------------
-- This bus is used to access all external memory and IO, it can also, via configuration, be used to read instructions from attached memory.
--
-- MEM_WRITE_ENABLE     - set to '1' for a single cycle to send off a write request.
--                        MEM_DATA_OUT is valid only while MEM_WRITE_ENABLE='1'.
-- MEM_WRITE_BYTE       - set to '1' when performing a byte write with data in bits 7-0 of MEM_DATA_OUT 
-- MEM_WRITE_HWORD      - set to '1' when performing a half word write with data in bits 15-0 of MEM_DATA_OUT 
-- MEM_READ_ENABLE      - set to '1' for a single cycle to send off a read request. Data is expected on MEM_DATA_IN on next clock rising edge 
--                        unless MEM_BUSY is asserted in which case the data is read on the next clock rising edge after MEM_BUSY is
--                        de-asserted.
-- 
-- MEM_BUSY             - This signal is used to prolong a read or write cycle, whilst asserted, any read or write cycle is paused as is the
--                        CPU with signals remaining in same state just prior to MEM_BUSY assetion.
--                        Set to '0' when MEM_READ is valid after a read request.
--                        If set to '1'(busy), the current cycle is held until released. For MEM_READ_ENABLE = '1' this means data will be
--                        latched on clock rising edge following deassertion of MEM_BUSY. For MEM_WRITE_ENABLE, the write transaction is held
--                        with MEM_WRITE_ENABLE asserted until the cycle following the deassertion of MEM_BUSY.
-- MEM_ADDR             - address for read/write request
-- MEM_DATA_IN          - read data. Valid only on the cycle after mem_busy='0' after 
--                        MEM_READ_ENABLE='1' for a single cycle.
-- MEM_DATA_OUT         - data to write
--
-- Wishbone Bus B4 Specification
-- -----------------------------
-- This bus is the industry standard for FPGA IP designs and the one primarily used in OpenCores. In this implementation it is
-- 32bit wide using a Master/Multi-Slave configuration with the ZPU acting as Master. It is a compile time configurable extension as
-- some uses of the ZPU Evo wont need it and thus saves fabric area. The description below is taken from the OpenCores Wishbone B4 
-- specification.
--
-- WB_CLK_I             - The clock input [WB_CLK_I] coordinates all activities for the internal logic within the WISHBONE interconnect.
--                      - All WISHBONE output signals are registered at the rising edge of [WB_CLK_I]. All WISHBONE input signals are
--                      - stable before the rising edge of [WB_CLK_I].
-- WB_RST_I             - The reset input [WB_RST_I] forces the WISHBONE interface to restart. In this design,  this signal is tied to the
--                      - ZPU reset via an OR mechanism, forcing the ZPU to reset if activated.
-- WB_ACK_I             - The acknowledge input [WB_ACK_I], when asserted, indicates the normal termination of a bus cycle.
-- WB_DAT_I             - The data input array [WB_DAT_I] is used to pass binary data. The array boundaries are determined by the port size,
--                      - with a port size of 32-bits in this design.
-- WB_DAT_O             - The data output array [DAT_O()] is used to pass binary data. The array boundaries are determined by the port size,
--                      - with a port size of 32-bits in this design.
-- WB_ADR_O             - The address output array [WB_ADR_O] is used to pass a binary address. The higher array boundary is specific to the
--                      - address width of the core, and the lower array boundary is determined by the data port size and granularity.
--                      - This design is 32bit so WB_ADR[1:0] specify the byte level granularity.
-- WB_CYC_O             - The cycle output [WB_CYC_O], when asserted, indicates that a valid bus cycle is in progress. The signal is asserted
--                      - for the duration of all bus cycles.
-- WB_STB_O             - The strobe output [WB_STB_O] indicates a valid data transfer cycle. It is used to qualify various other signals on
--                      - the interface such as [WB_SEL_O]. The SLAVE asserts either the [WB_ACK_I], [WB_ERR_I] or [WB_RTY_I] signals in
--                      - response to every assertion of the [WB_STB_O] signal.
-- WB_CTI_O             - The Cycle Type Idenfier [WB_CTI_O] Address Tag provides additional information about the current cycle. The MASTER
--                      - sends this information to the SLAVE. The SLAVE can use this information to prepare the response for the next cycle.
-- WB_WE_O              - The write enable output [WB_WE_O] indicates whether the current local bus cycle is a READ or WRITE cycle. The
--                      - signal is negated during READ cycles, and is asserted during WRITE cycles.
-- WB_SEL_O             - The select output array [WB_SEL_O] indicates where valid data is expected on the [WB_DAT_I] signal array during
--                      - READ cycles, and where it is placed on the [WB_DAT_O] signal array during WRITE cycles. The array boundaries are
--                      - determined by the granularity of a port which is 32bit in this design leading to a WB_SEL_O width of 4 bits, 1
--                      - bit to represent each byte. ie. WB_SEL_O[3] = MSB, WB_SEL_O[0] = LSB.
-- WB_HALT_I            - 
-- WB_ERR_I             - The error input [WB_ERR_I] indicates an abnormal cycle termination. The source of the error, and the response
--                      - generated by the MASTER is defined by the IP core supplier, in this case the intention (NYI) is to retry
--                      - the transaction.
-- WB_INTA_I            - A non standard signal to allow a wishbone device to interrupt the ZPU when set to logic '1'. The interrupt is
--                      - registered on the next rising edge.
--
--
-- Instruction Memory Bus
-- ----------------------
-- This bus is used for dedicated faster response read only memory containing the code to be run. Using this bus results in faster
-- CPU performance. If this bus is not used/disabled, all instructions will be fetched via the main bus (System or Wishbone bus).
--
-- MEM_BUSY_INSN        - Memory is busy ('1') so data invalid.
-- MEM_DATA_IN_INSN     - Instruction data in.
-- MEM_ADDR_INSN        - Instruction address bus.
-- MEM_READ_ENABLE_INSN - Instruction read enable signal (active high).
--
-- INT_REQ              - Set to '1' by external logic until interrupts are acknowledged by CPU. 
-- INT_ACK              - Set to '1' for 1 clock cycle when the interrupt is acknowledged and processing commences.
-- INT_DONE             - Set to '1' for 1 clock cycle when the interrupt processing is complete
-- BREAK                - Set to '1' when CPU hits a BREAK instruction
-- CONTINUE             - When the CPU is halted due to a BREAK instruction, this signal, when asserted ('1') forces the CPU to commence
--                        processing of the instruction following the BREAK instruction.
-- DEBUG_TXD            - Serial output of runtime debug data if enabled.
 
entity zpu_core_evo is
    generic (
        -- Optional hardware features to be implemented.
        IMPL_HW_BYTE_WRITE        : boolean := false;       -- Enable use of hardware direct byte write rather than read 32bits-modify 8 bits-write 32bits.
        IMPL_HW_WORD_WRITE        : boolean := false;       -- Enable use of hardware direct byte write rather than read 32bits-modify 16 bits-write 32bits.
        IMPL_OPTIMIZE_IM          : boolean := true;        -- Optimise Im instructions to gain speed.
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
        IMPL_MOD                  : boolean := true;        -- 32bit modulo (remainder after division).
        IMPL_MULT                 : boolean := true;        -- 32bit signed multiplication.
        IMPL_NEG                  : boolean := true;        -- Negate value in TOS.
        IMPL_NEQ                  : boolean := true;        -- Not equal test.
        IMPL_POPPCREL             : boolean := true;        -- Pop a value into the Program Counter from a location relative to the Stack Pointer.
        IMPL_PUSHSPADD            : boolean := true;        -- Add a value to the Stack pointer and push it onto the stack.
        IMPL_STOREB               : boolean := true;        -- Store/Write a single byte to memory/IO.
        IMPL_STOREH               : boolean := true;        -- Store/Write a half word (16bit) to memory/IO.
        IMPL_SUB                  : boolean := true;        -- 32bit signed subtract.
        IMPL_XOR                  : boolean := true;        -- Exclusive or of value in TOS.
        -- Size/Control parameters for the optional hardware.
        MAX_INSNRAM_SIZE          : integer := 16384;       -- Maximum size of the optional Instruction BRAM on the INSN Bus.
        MAX_L1CACHE_BITS          : integer := 4;           -- Maximum size in instructionsG of the Level 0 instruction cache governed by the number of bits, ie. 8 = 256 instruction cache.
        MAX_L2CACHE_BITS          : integer := 12;          -- Maximum size in bytes of the Level 1 instruction cache governed by the number of bits, ie. 8 = 256 byte cache.
        MAX_MXCACHE_BITS          : integer := 3;           -- Maximum size of the memory transaction cache governed by the number of bits.
        RESET_ADDR_CPU            : integer := 0;           -- Initial start address of the CPU.
        START_ADDR_MEM            : integer := 0;           -- Start address of program memory.
        STACK_ADDR                : integer := 0;           -- Initial stack address on CPU start.
        CLK_FREQ                  : integer := 100000000    -- Frequency of the input clock.
    );
    port (
        CLK                       : in  std_logic;          -- Main clock.
        RESET                     : in  std_logic;          -- Reset the CPU (high).
        ENABLE                    : in  std_logic;          -- Enable the CPU (high), setting low will halt the CPU until signal is returned high.
        -- Main Memory/IO bus.
        MEM_BUSY                  : in  std_logic; 
        MEM_DATA_IN               : in  std_logic_vector(WORD_32BIT_RANGE);
        MEM_DATA_OUT              : out std_logic_vector(WORD_32BIT_RANGE);
        MEM_ADDR                  : out std_logic_vector(ADDR_BIT_RANGE);
        MEM_WRITE_ENABLE          : out std_logic; 
        MEM_READ_ENABLE           : out std_logic;
        MEM_WRITE_BYTE            : out std_logic;
        MEM_WRITE_HWORD           : out std_logic;
        MEM_BUSRQ                 : in  std_logic;          -- Bus request, when memory transaction processor goes to Idle, suspend and allow an external device to control the bus.
        MEM_BUSACK                : out std_logic;          -- Bus acknowledge, set when MEM_BUSRQ goes active and the memory transaction processor completes a transaction and goes idle.
        -- Instruction memory bus (if implemented).
        MEM_BUSY_INSN             : in  std_logic; 
        MEM_DATA_IN_INSN          : in  std_logic_vector(WORD_64BIT_RANGE);
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
end zpu_core_evo;

architecture behave of zpu_core_evo is

    -- Constants.
    constant MAX_L1CACHE_SIZE     :  integer := (2**(MAX_L1CACHE_BITS));
    constant MAX_L2CACHE_SIZE     :  integer := (2**MAX_L2CACHE_BITS);
    subtype  L1CACHE_BIT_RANGE    is natural range MAX_L1CACHE_BITS-1 downto 0;
    subtype  L2CACHE_BIT_RANGE    is natural range MAX_L2CACHE_BITS-1 downto 0;
    subtype  L2CACHE_32BIT_RANGE  is natural range MAX_L2CACHE_BITS-1 downto 2;
    subtype  L2CACHE_64BIT_RANGE  is natural range MAX_L2CACHE_BITS-1 downto 3;

    -- Instruction offset in the instruction vector.
    subtype  INSN_RANGE           is natural range  13 downto   0;
    subtype  OPCODE_RANGE         is natural range   7 downto   0;
    subtype  DECODED_RANGE        is natural range  13 downto   8;
    subtype  OPCODE_IM_RANGE      is natural range   6 downto   0;
    subtype  IM_DATA_RANGE        is natural range   6 downto   0;
    subtype  OPCODE_PARAM_RANGE   is natural range   1 downto   0;
    subtype  OPCODE_INSN_RANGE    is natural range   7 downto   2;

    -- Decoded instruction states. Used in the execution unit state machine according to instruction being processed.
    type InsnType is 
    (
        Insn_Add,                      -- 00
        Insn_AddSP,                    -- 01
        Insn_AddTop,                   -- 02
        Insn_Alshift,                  -- 03
        Insn_And,                      -- 04
        Insn_Break,                    -- 05
        Insn_Call,                     -- 06
        Insn_Callpcrel,                -- 07
        Insn_Div,                      -- 08
        Insn_Emulate,                  -- 09
        Insn_Eq,                       -- 0a
        Insn_Eqbranch,                 -- 0b
        Insn_Extend,                   -- 0c
        Insn_FiAdd32,                  -- 0d
        Insn_FiDiv32,                  -- 0e
        Insn_FiMult32,                 -- 0f
        Insn_Flip,                     -- 10
        Insn_Im,                       -- 11
        Insn_Lessthan,                 -- 12
        Insn_Lessthanorequal,          -- 13
        Insn_Load,                     -- 14
        Insn_Loadb,                    -- 15
        Insn_Loadh,                    -- 16
        Insn_LoadSP,                   -- 17
        Insn_Mod,                      -- 18
        Insn_Mult,                     -- 19
        Insn_Neg,                      -- 1a
        Insn_Neq,                      -- 1b
        Insn_Neqbranch,                -- 1c
        Insn_Nop,                      -- 1d
        Insn_Not,                      -- 1e
        Insn_Or,                       -- 1f
        Insn_PopPC,                    -- 20 
        Insn_PopPCRel,                 -- 21
        Insn_PopSP,                    -- 22
        Insn_PushPC,                   -- 23
        Insn_PushSP,                   -- 24
        Insn_Pushspadd,                -- 25
        Insn_Shift,                    -- 26
        Insn_Store,                    -- 27
        Insn_Storeb,                   -- 28
        Insn_Storeh,                   -- 29
        Insn_StoreSP,                  -- 2a
        Insn_Sub,                      -- 2b
        Insn_Ulessthan,                -- 2c
        Insn_Ulessthanorequal,         -- 2d
        Insn_Xor                       -- 2e
    );
    
    -- State machine states. Some states are extension of instruction execution whilst others maintain the ZPU runtime operations and state.
    --
    type StateType is 
    (
        State_Div2,
        State_Mult2,
        State_Execute,
        State_FiAdd2,
        State_FiDiv2,
        State_FiMult2,
        State_Idle,
        State_Init,
        State_Mod2
    ); 
    
    -- Decoder state machine states. Unit which fetches, decodes and stores the decoded instructions and the required states needed to do this.
    --
    type DecoderStateType is 
    (
        Decode_Idle,
        Decode_Fetch,
        Decode_Word,
        Decode_WriteCache
    );

    type Level1CacheStateType is
    (
        State_PreSetAddr,
        State_LatchAddr,
        State_Decode,
        State_Store
    );
    
    -- Memory transaction processing unit. All CPU memory accesses (except Instruction Fetch) go through this unit. These states define
    -- those required to implement the unit.
    --
    type MemXactStateType is
    (
        MemXact_Idle,
        MemXact_MemoryFetch,
        MemXact_OpcodeFetch,
        MemXact_TOS,
        MemXact_NOS,
        MemXact_TOSNOS,
        MemXact_TOSNOS_2,
        MemXact_TOSNOS_3,
        MemXact_ReadByteToTOS,
        MemXact_ReadWordToTOS,
        MemXact_ReadAddToTOS,
        MemXact_WriteToAddr,
        MemXact_WriteByteToAddr,
        MemXact_WriteByteToAddr2,
        MemXact_WriteHWordToAddr,
        MemXact_WriteHWordToAddr2
    );
    
    -- Memory transaction processing commands. These states (commands) are the actions which the MTP can process.
    --
    type MemXactCmdType is
    (
        MX_CMD_READTOS,
        MX_CMD_READNOS,
        MX_CMD_READTOSNOS,
        MX_CMD_READBYTETOTOS,
        MX_CMD_READWORDTOTOS,
        MX_CMD_READADDTOTOS,
        MX_CMD_WRITEBYTETOADDR,
        MX_CMD_WRITEHWORDTOADDR,
        MX_CMD_WRITETOINDADDR,
        MX_CMD_WRITE
    );
    
    -- Debug states. These states are those required to output debug data via the debug serialisation unit.
    --
    type DebugType is 
    (
        Debug_Idle,
        Debug_Start,
        Debug_DumpL1,
        Debug_DumpL1_1,
        Debug_DumpL1_2,
        Debug_DumpL2,
        Debug_DumpL2_0,
        Debug_DumpL2_1,
        Debug_DumpL2_2,
        Debug_DumpMem,
        Debug_DumpMem_0,
        Debug_DumpMem_1,
        Debug_DumpMem_2,
        Debug_End
    );
    
    -- Record to store a memory word and its validity, typically used for stack caching.
    --
    type WordRecord is record
        word                               : unsigned(WORD_32BIT_RANGE);
        valid                              : std_logic;
    end record;
    
    -- Record to contain an opcode and its decoded form.
    --
    type InsnRecord is record
        decodedOpcode                      : InsnType;
        opcode                             : std_logic_vector(7 downto 0);
    end record;
    
    -- Memory transaction records. Memory reads and writes are pushed into a queue and executed sequentially.
    --
    type MemXactRecord is record
        addr                               : std_logic_vector(ADDR_BIT_RANGE);
        data                               : std_logic_vector(WORD_32BIT_RANGE);
        cmd                                : MemXactCmdType;
    end record;
    --
    -- Array definitions.
    type InsnWord     is array(natural range 0 to wordBytes-1) of InsnRecord;
    type InsnQueue    is array(natural range 0 to 2*wordBytes-1) of InsnRecord;
    type InsnL1Array  is array(natural range 0 to ((2**(MAX_L1CACHE_BITS))-1)) of std_logic_vector(INSN_RANGE);
    type MemXactArray is array(natural range 0 to ((2**MAX_MXCACHE_BITS)-1)) of MemXactRecord;
    
    signal pc                              : unsigned(ADDR_BIT_RANGE);                  -- Current program location being executed.
    signal incPC                           : unsigned(ADDR_BIT_RANGE);                  -- Next program location to be executed.
    signal incIncPC                        : unsigned(ADDR_BIT_RANGE);                  -- Next +2 program location to be executed.
    signal inc3PC                          : unsigned(ADDR_BIT_RANGE);                  -- Next +3 program location to be executed.
    signal inc4PC                          : unsigned(ADDR_BIT_RANGE);                  -- Next +4 program location to be executed.
    signal inc5PC                          : unsigned(ADDR_BIT_RANGE);                  -- Next +5 program location to be executed.
    signal sp                              : unsigned(ADDR_32BIT_RANGE);                -- Current stack pointer.
    signal incSp                           : unsigned(ADDR_32BIT_RANGE);                -- Stack pointer when 1 value is popped.
    signal incIncSp                        : unsigned(ADDR_32BIT_RANGE);                -- Stack pointer when 2 values are popped.
    signal decSp                           : unsigned(ADDR_32BIT_RANGE);                -- Stack pointer after a value is pushed.
    signal TOS                             : WordRecord;                                -- Top Of Stack value.
    signal NOS                             : WordRecord;                                -- Next Of Stack value (ie. value after TOS).
    signal mxTOS                           : WordRecord;                                -- Top Of Stack retrieved by the Memory Transaction Processor.
    signal mxNOS                           : WordRecord;                                -- Next Of Stack retrieved by the MXP.
    signal muxTOS                          : WordRecord;                                -- Multiplexed (to get most recent) TOS, either from MXP or current value.
    signal muxNOS                          : WordRecord;                                -- Multiplexed (to get most recent) NOS, either from MXP or current value.
    signal divResult                       : unsigned(WORD_32BIT_RANGE);
    signal divRemainder                    : unsigned(WORD_32BIT_RANGE);
    signal divStart                        : std_logic;
    signal divComplete                     : std_logic;
    signal quotientFractional              : integer range 0 to 15;                     -- Fractional component size of a fixed point value.
    signal divQuotientFractional           : integer range 0 to 15;                     -- Fractional component size for the divider as it can be changed dynamically for integer division.
    signal multResult                      : unsigned(wordSize*2-1 downto 0);           -- Result after internal multiplication.
    signal state                           : StateType;
    signal fpAddResult                     : std_logic_vector(WORD_32BIT_RANGE);
    signal fpMultResult                    : std_logic_vector(WORD_32BIT_RANGE);
    signal bitCnt                          : unsigned(5 downto 0);
    signal dividendCopy                    : std_logic_vector(61 downto 0);
    signal divisorCopy                     : std_logic_vector(61 downto 0);

    -- Wishbone processing.
    --
    signal ZPURESET                        : std_logic;
    signal wbXactActive                    : std_logic;                                 -- Wishbone interface is active.
    
    -- Break processing.
    --
    signal inBreak                         : std_logic;                                 -- Flag to indicate when the CPU is halted (1) due to a BREAK instruction or illegal instruction.
    
    -- Interrupt procesing.
    --
    signal intTriggered                    : std_logic;                                 -- Flag to indicate an interrupt has been requested, reset when interrupt processing starts.
    signal inInterrupt                     : std_logic;                                 -- Flag to indicate that the CPU is currently inside an interrupt processing block.
    signal interruptSuspendedAddr          : unsigned(ADDR_BIT_RANGE);                  -- Address that was interrupted by the interrupt, used to return processing when interrupt complete.
    
    -- Instruction storage, decoding and processing.
    --
    signal insnExParameter                 : unsigned(WORD_32BIT_RANGE);                -- Parameter storage for the extended instruction.
    signal idimFlag                        : std_logic;                                 -- Flag to indicate concurrent Im instructions which are building a larger word in TOS.
    signal l1State                         : Level1CacheStateType;                      -- Current state of the L1 Cache decode and populate machine.
    
    -- Cache L1 specific signals.
    --
    signal cacheL1                         : InsnL1Array;                               -- Level 1 cache, implemented as registers to gain random access for instruction lookahead optimisation and instruction set extension.
    signal cacheL1StartAddr                : unsigned(ADDR_BIT_RANGE);                  -- Absolute address of first instruction in cache.
    signal cacheL1FetchIdx                 : unsigned(ADDR_BIT_RANGE);                  -- Index into L1 cache decoded instructions will be placed.
    signal cacheL1Invalid                  : std_logic;                                 -- A flag to indicate when the L1 cache is in invalid.
    signal cacheL1Empty                    : std_logic;                                 -- A flag to indicate when the L1 cache is empty.
    signal cacheL1Full                     : std_logic;                                 -- A flag to indicate when the L1 cache is full.
    signal cacheL1InsnAfterPC              : unsigned(ADDR_BIT_RANGE);                  -- Count of how many instructions are in the cache after the current program counter.
    attribute ramstyle                     : string;
    attribute ramstyle of cacheL1          : signal is "logic";                         -- Force the compiler to use registers for the L1 cache.
    
    -- Cache L2 (primary) specific signals.
    --
    signal cacheL2FetchIdx                 : unsigned(ADDR_BIT_RANGE);                  -- Location in memory being read by the decoder for storage into cache.
    signal cacheL2StartAddr                : unsigned(ADDR_BIT_RANGE);                  -- The actual program address stored in the first cache location.
    signal cacheL2Active                   : std_logic;                                 -- A flag to indicate when the L2 cache is in use.
    signal cacheL2Invalid                  : std_logic;                                 -- A flag to indicate when the L2 cache is in invalid.
    signal cacheL2Empty                    : std_logic;                                 -- A flag to indicate the instruction cache is empty.
    signal cacheL2Mux2Addr                 : unsigned(L2CACHE_64BIT_RANGE);             -- Multiplexed address into L2 cache between the L1 fetch and debug fetch.
    signal cacheL2Word                     : std_logic_vector(WORD_64BIT_RANGE);        -- A 64bit long word containing the next instructions to be read/written from L2 cache.
    signal cacheL2Write                    : std_logic;                                 -- Flag to indicate a write to L2 cache should be made.
    signal cacheL2WriteByte                : std_logic;                                 -- Update a single byte in the L2 cache.
    signal cacheL2WriteHword               : std_logic;                                 -- Update a 16bit half-word in the L2 cache.
    signal cacheL2WriteAddr                : unsigned(L2CACHE_BIT_RANGE);               -- Address in L2 cache for next operation.
    signal cacheL2WriteData                : std_logic_vector(WORD_32BIT_RANGE);        -- A 32bit word, from main memory, to be written into the 32/64 L2 cache.
    signal cacheL2IncAddr                  : std_logic;                                 -- A flag to indicate when the L2 cache write address should be incremented, generally after a write pulse.
    signal cacheL2MxAddrInCache            : std_logic;                                 -- A flag to indicate when an MXP address exists in the L2 cache.
    signal cacheL2Full                     : std_logic;                                 -- A flag to indicate when the L2 cache is full.
    signal cacheL2InsnAfterPC              : unsigned(ADDR_BIT_RANGE);                  -- Count of how many instructions are in the cache after the current program counter.
    
    -- Memory transaction processor.
    --
    signal mxFifo                          : MemXactArray;                              -- MXP Fifo (circular) queue. This queue contains the commands the MXP should process.
    signal mxState                         : MemXactStateType;                          -- MXP Finite State Machine state.
    signal mxFifoWriteIdx                  : unsigned(MAX_MXCACHE_BITS-1 downto 0);     -- Next location to write a command in the MXP circular queue.
    signal mxFifoReadIdx                   : unsigned(MAX_MXCACHE_BITS-1 downto 0);     -- Next MXP circular queue location where a command is taken.
    signal mxXactSlotsFree                 : unsigned(MAX_MXCACHE_BITS-1 downto 0);     -- Number of Memory transaction processor command slots free in it's queue.
    signal mxXactSlotsUsed                 : unsigned(MAX_MXCACHE_BITS-1 downto 0);     -- Number of Memory transaction processor command slots occupied in it's queue.
    signal mxMemVal                        : WordRecord;                                -- Direct memory read result.
    signal mxHoldCycles                    : integer range 0 to 3;                      -- Cycles to hold and extend memory transactions.
    signal mxSuspend                       : std_logic;                                 -- Signal to suspend memory transaction processing when set to 1.
    
    -- Hardware Debugging.
    --
    signal debugPC                         : unsigned(ADDR_BIT_RANGE);                  -- Debug PC for reading L1, L2 and memory for debugger output.
    signal debugPC_StartAddr               : unsigned(ADDR_BIT_RANGE);                  -- Start address for dump of memory contents.
    signal debugPC_EndAddr                 : unsigned(ADDR_BIT_RANGE);                  -- End address for dump of memory contents.
    signal debugPC_Width                   : integer range 8 to 32;                     -- Width of output in bytes.
    signal debugPC_WidthCounter            : integer range 0 to 31;                     -- Counter to match variable width.
    signal debugState                      : DebugType;                                 -- Debugger Finite State Machine state.
    signal debugOutputOnce                 : std_logic;                                 -- Signal to prevent continuous output of debug messages when in a wait.
    signal debugAllInfo                    : std_logic;                                 -- Output all information from start point of entry to debug FSM if set.
    signal debugRec                        : zpu_dbg_t;                                 -- A complex register record for placing data to be serialised by the debug serialiser.
    signal debugLoad                       : std_logic;                                 -- Load a debug record into the debug serialiser fsm, 1 = load, 0 = inactive.
    signal debugReady                      : std_logic;                                 -- Flag to indicate serializer fsm is busy (0) or available (1).

    ---------------------------------------------
    -- Functions specific to the CPU core.
    ---------------------------------------------

begin
    -- If the wishbone interface is enabled, assign permanent connections.
    WB_INIT: if IMPL_USE_WB_BUS = true generate
        ZPURESET                           <= RESET or WB_RST_I;
    else generate
        ZPURESET                           <= RESET;
    end generate;

    ---------------------------------------------
    -- Cache storage.
    ---------------------------------------------
    
    -- Level 2 cache inferred with byte level write.
    --
    CACHEL2 : work.evo_L2cache
    generic map (
        addrbits                           => MAX_L2CACHE_BITS
    )
    port map (
        clk                                => CLK,
        memAAddr                           => std_logic_vector(cacheL2WriteAddr),
        memAWriteEnable                    => cacheL2Write,
        memAWriteByte                      => cacheL2WriteByte,
        memAWriteHalfWord                  => cacheL2WriteHword,
        memAWrite                          => cacheL2WriteData,
        memARead                           => open,

        memBAddr                           => std_logic_vector(cacheL2Mux2Addr),
        memBWrite                          => (others => '0'),
        memBWriteEnable                    => '0',
        memBRead                           => cacheL2Word
    );
    
    -- Instruction cache memory. cache instructions from the resync program counter forwards, when we get to a relative or direct
    -- jump, if the destination is in cache, read from cache else resync. This speeds up operations where a resync (ie. branch, call etc) would
    -- occur, saving cycles. It more especially speeds up the process if using one main bus and the external memory speed is slower than bram.
    --
    -- Description of signals:
    -- cacheL2StartAddr       Absolute Start Address of word in first cache location.
    -- cacheL2Active          1 when L2 cache is active, 0 when using dedicated instruction BRAM.
    -- cacheL2Empty           1 when cache is empty, 0 when valid data present.
    -- cacheL2Invalid         1 when the contents of L2Cache are no longer valid (due to next insn being out of cache scope).
    -- cacheL2Mux2Addr        Address multiplexer into cache. Address is set to the DebugPC address when the Debug state machine is not idle, all other times it is set to the Next cache fetch address.
    -- cacheL2MxAddrInCache   When a queued MX Processor address is in the L2 cache, set to 1 else set to 0. Used to determine if a memory write should be written into cache (write thru).
    -- cacheL2Full            1 when cache is full, 0 otherwise.
    -- mxXactSlotsFree        Number of slots available in the MXP queue for placing commands.
    -- mxXactSlotsUsed        Number of slots in the MXP queue filled with commands to be executed.
    --
    cacheL2Active                          <= '1' when IMPL_USE_INSN_BUS = false or (IMPL_USE_INSN_BUS = true and pc >= to_unsigned(MAX_INSNRAM_SIZE, pc'length))
                                                  else '0';
    cacheL2Empty                           <= '1' when cacheL2FetchIdx(ADDR_64BIT_RANGE) <= cacheL2StartAddr(ADDR_64BIT_RANGE)
                                                  else '0';
    cacheL2Invalid                         <= '0' when pc >= cacheL2StartAddr and pc < cacheL2FetchIdx and cacheL2FetchIdx(ADDR_64BIT_RANGE) > cacheL2StartAddr(ADDR_64BIT_RANGE) and mxSuspend = '0'
                                                  else '1';
    cacheL2Mux2Addr                        <= cacheL1FetchIdx(L2CACHE_64BIT_RANGE) when DEBUG_CPU = false or (DEBUG_CPU = true and debugState = Debug_Idle)
                                                  else
                                                  debugPC(L2CACHE_64BIT_RANGE)     when DEBUG_CPU = true
                                                  else
                                                  (others => 'X');
    cacheL2MxAddrInCache                   <= '1' when (to_unsigned(to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr)), cacheL2StartAddr'length) >= cacheL2StartAddr and to_unsigned(to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr)), cacheL2FetchIdx'length) < cacheL2FetchIdx) 
                                                       and 
                                                       (IMPL_USE_INSN_BUS = false or (IMPL_USE_INSN_BUS = true and unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr) >= to_unsigned(MAX_INSNRAM_SIZE, mxFifo(to_integer(mxFifoReadIdx)).addr'length)))
                                                  else '0';
    cacheL2Full                            <= '1' when cacheL2FetchIdx(ADDR_32BIT_RANGE) - cacheL2StartAddr(ADDR_32BIT_RANGE) = MAX_L2CACHE_SIZE / 4
                                                  else '0';
    cacheL2InsnAfterPC                     <= cacheL2FetchIdx - pc when cacheL2Invalid = '0' 
                                              else to_unsigned(0, cacheL2InsnAfterPC'length);
    mxXactSlotsFree                        <= to_unsigned((2**MAX_MXCACHE_BITS)-1, MAX_MXCACHE_BITS) - (mxFifoWriteIdx - mxFifoReadIdx);
    mxXactSlotsUsed                        <= mxFifoWriteIdx - mxFifoReadIdx;
    ---------------------------------------------
    -- End of Cache storage.
    ---------------------------------------------

    ------------------------------------
    -- Memory transaction processor MXP.
    ------------------------------------
    -- The mxp localises all memory/io operations into a single process. This aids in adaptation to differing bus topolgies as only this process
    -- needs updating (the local INSN bus uses a direct BRAM/ROM connection and bypasses the MXP). This logic processes a queue of transactions in fifo
    -- order and fetches instructions as required.. The processor unit commits requests to the queue and this logic fulfills them. If the CPU is only
    -- using one bus for all memory and IO operations then memory transactions in the queue are completed before instruction fetches. If the instruction
    -- queue is empty then the processor will stall until instructions are fetched.
    --
    MEMXACT: process(CLK, ZPURESET, TOS, NOS, debugState)
    begin
        ------------------------
        -- HIGH LEVEL         --
        ------------------------
    
        ------------------------
        -- ASYNCHRONOUS RESET --
        ------------------------
        if ZPURESET = '1' then
            MEM_WRITE_BYTE                                   <= '0';
            MEM_WRITE_HWORD                                  <= '0';
            MEM_READ_ENABLE                                  <= '0';
            MEM_WRITE_ENABLE                                 <= '0';
            MEM_BUSACK                                       <= '1';                               -- During RESET the bus is made available to external devices.
            WB_ADR_O(ADDR_32BIT_RANGE)                       <= (others => '0');
            WB_DAT_O                                         <= (others => '0');
            WB_WE_O                                          <= '0';
            WB_CYC_O                                         <= '0';
            WB_STB_O                                         <= '0';
            WB_CTI_O                                         <= "000";
            WB_SEL_O                                         <= "1111";
            wbXactActive                                     <= '0';
            cacheL2Write                                     <= '0';
            cacheL2IncAddr                                   <= '0';
            cacheL2FetchIdx                                  <= (others => '0');
            cacheL2StartAddr                                 <= (others => '0');
            mxFifoReadIdx                                    <= (others => '0');
            mxState                                          <= MemXact_Idle;
            mxSuspend                                        <= '0';
            mxTOS                                            <= ((others => '0'), '0');
            mxNOS                                            <= ((others => '0'), '0');
            mxHoldCycles                                     <= 0;
            if DEBUG_CPU = true then
                mxMemVal.valid                               <= '0';
            end if;

        ------------------------
        -- FALLING CLOCK EDGE --
        ------------------------
        elsif falling_edge(CLK) then
    
            -- TOS and NOS are multiplexed between an immediate result from the MXP (which is latched on the subsequent clock) and the latched value. The valid
            -- flag indicates which to use.
--            muxTOS.valid                                     <= mxTOS.valid or TOS.valid;
--            if  mxTOS.valid = '1' then
--                muxTOS.word                                  <= mxTOS.word;
--            else
--                muxTOS.word                                  <= TOS.word;
--            end if;
--            muxNOS.valid                                     <= mxNOS.valid or NOS.valid;
--            if  mxNOS.valid = '1' then
--                muxNOS.word                                  <= mxNOS.word;
--            else
--                muxNOS.word                                  <= NOS.word;
--            end if;

        -----------------------
        -- RISING CLOCK EDGE --
        -----------------------
        elsif rising_edge(CLK) then

            -- TOS/NOS values read in by the MXP are only valid for 1 cycle, so reset the valid flag.
            mxTOS.valid                                      <= '0';
            mxNOS.valid                                      <= '0';

            -- Memory signals are one clock width wide unless extended by a wait, if no wait, reset them to inactive to ensure this.
            if MEM_BUSY = '0' then
                MEM_READ_ENABLE                              <= '0';
                MEM_WRITE_ENABLE                             <= '0';

                -- Width signals are one clock width wide unless extended by a wait signal.
                MEM_WRITE_BYTE                               <= '0';
                MEM_WRITE_HWORD                              <= '0';
            end if;

            -- Complete any active cache memory writes.
            if cacheL2Write = '1' and mxHoldCycles = 0 then
                cacheL2Write                                 <= '0';
                cacheL2WriteByte                             <= '0';
                cacheL2WriteHword                            <= '0';

                -- Once the cache write is complete, we update the address if needed, which will be setup in time for the next word to be read in from external memory.
                if cacheL2IncAddr = '1' then
                    cacheL2IncAddr                           <= '0';

                    -- Update the address from where we fetch the next instruction, 32bit aligned 4 bytes.
                    cacheL2FetchIdx                          <= cacheL2FetchIdx + wordBytes;
                end if;
            end if;

            -- If wishbone interface is active and an ACK is received, deassert the signals.
            if IMPL_USE_WB_BUS = true and wbXactActive = '1' and WB_ACK_I = '1' and WB_HALT_I = '0' and mxHoldCycles = 0 then
                wbXactActive                                 <= '0';
                WB_WE_O                                      <= '0';
                WB_CYC_O                                     <= '0';
                WB_STB_O                                     <= '0';
            end if;

            -- TODO: WB_ERR_I needs better handling, should retry at least once and then issue a BREAK.
            if IMPL_USE_WB_BUS = true and WB_ERR_I = '1' then
                wbXactActive                                 <= '0';
                WB_WE_O                                      <= '0';
                WB_CYC_O                                     <= '0';
                WB_STB_O                                     <= '0';
            end if;

            -- Memory bus released after being granted, release the bus.
            if MEM_BUSRQ = '0' then
                mxSuspend                                    <= '0';
                MEM_BUSACK                                   <= '0';
            end if;

            -- If the hold cycle counter is not 0, then we are holding on the current transaction until it reaches zero, so decrement
            -- ready to test next cycle. This mechanism is to prolong a memory cycle as without it, address setup and hold is 1 cycle and 
            -- valid data is expected at the end of the cycle. ie. the address and control signals are set on the current rising edge and become
            -- active and on the next rising edge the data is expected to be valid, few components (ie. register ram) can meet this timing requirement.
            if mxHoldCycles > 0 then
                mxHoldCycles                             <= mxHoldCycles - 1;
            end if;

            -- When a bus request is made, wait until the mxp is idle, this is important as the mxp could read/write memory which gets updated by an external device.
            if MEM_BUSRQ = '1' and MEM_BUSY = '0' and mxState = MemXact_Idle and mxXactSlotsUsed = 0 then
                mxSuspend                                    <= '1';
                MEM_BUSACK                                   <= '1';
            else

                -- If the external memory is busy (1) or the wishbone interface is active and no ACK received then we have to back off and wait till next clock cycle and check again.
                if MEM_BUSY = '0' and mxSuspend = '0' and mxHoldCycles = 0 and ((IMPL_USE_WB_BUS = true and ((wbXactActive = '1' and WB_ACK_I = '1') or wbXactActive = '0')) or IMPL_USE_WB_BUS = false) then

                    -- Memory transaction processor state machine. Idle is the control state and depending upon entries in the queue, debug or L2 usage, it
                    -- directs the FSM states accordingly. 
                    case mxState is

                        when MemXact_Idle =>
    
                            -- If there is an item on the queue and the memory system isnt busy from a previous operation, process
                            -- the queue item.
                            --
                            if mxXactSlotsUsed > 0 then
    
                                -- Setup the address from the queue element and process the command.
                                if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                    WB_ADR_O(ADDR_32BIT_RANGE)          <= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                    WB_ADR_O(minAddrBit-1 downto 0)     <= (others => '0');
                                    WB_CTI_O                            <= "000";
                                    WB_SEL_O                            <= "1111";
                                    WB_WE_O                             <= '0';
                                    WB_CYC_O                            <= '1';
                                    WB_STB_O                            <= '1';
                                else
                                    MEM_ADDR(ADDR_32BIT_RANGE)          <= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                    MEM_ADDR(minAddrBit-1 downto 0)     <= (others => '0');
                                end if;
                                mxHoldCycles                            <= 1;

                                case mxFifo(to_integer(mxFifoReadIdx)).cmd is
                                    -- Read to TOS
                                    when MX_CMD_READTOS =>
                                        mxFifoReadIdx                   <= mxFifoReadIdx + 1;
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_TOS;
    
                                    -- Read to NOS
                                    when MX_CMD_READNOS =>
                                        mxFifoReadIdx                   <= mxFifoReadIdx + 1;
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_NOS;
    
                                    -- Read both TOS and NOS (save cycles).
                                    when MX_CMD_READTOSNOS =>
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_TOSNOS;
    
                                    -- Read Byte to TOS
                                    when MX_CMD_READBYTETOTOS =>
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_ReadByteToTOS;
    
                                    -- Read Word to TOS
                                    when MX_CMD_READWORDTOTOS =>
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_ReadWordToTOS;
    
                                    -- Read word and add to TOS
                                    when MX_CMD_READADDTOTOS =>
                                        mxFifoReadIdx                   <= mxFifoReadIdx + 1;
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_ReadAddToTOS;
    
                                    -- Write value to address
                                    when MX_CMD_WRITE =>
                                        mxFifoReadIdx                   <= mxFifoReadIdx + 1;
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            WB_DAT_O                    <= mxFifo(to_integer(mxFifoReadIdx)).data;
                                            WB_WE_O                     <= '1';
                                            wbXactActive                <= '1';
                                        else
                                            MEM_DATA_OUT                <= mxFifo(to_integer(mxFifoReadIdx)).data;
                                            MEM_WRITE_ENABLE            <= '1';
                                        end if;

                                        -- If the data write is to a cached location, update cache at same time.
                                        if cacheL2MxAddrInCache = '1' then
                                            cacheL2WriteAddr            <= unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(L2CACHE_BIT_RANGE));
                                            cacheL2WriteData            <= mxFifo(to_integer(mxFifoReadIdx)).data;

                                            -- Initiate a cache memory write.
                                            cacheL2Write                <= '1';
                                        end if;
                                        mxState                         <= MemXact_Idle;
                                        mxHoldCycles                    <= 2;
    
                                    -- Read value at address, then write data to the value's address.
                                    when MX_CMD_WRITETOINDADDR =>
                                        if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                            WB_WE_O                     <= '0';
                                            wbXactActive                <= '1';
                                        else
                                            MEM_READ_ENABLE             <= '1';
                                        end if;
                                        mxState                         <= MemXact_WriteToAddr;
mxHoldCycles                    <= 2;
    
                                    -- To write a byte, if hardware supports it, write out to the byte aligned address with data in bits 7-0 otherwise
                                    -- we first read the 32bit word, update it and write it back.
                                    when MX_CMD_WRITEBYTETOADDR =>
                                        -- If Hardware byte write not implemented or it is a write to the Startup ROM we have to resort
                                        -- to a read-modify-write operation.
                                        if IMPL_HW_BYTE_WRITE = false
                                        then
                                            if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                                wbXactActive            <= '1';
                                            else
                                                MEM_READ_ENABLE         <= '1';
                                            end if;
                                            cacheL2WriteAddr            <= unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(L2CACHE_32BIT_RANGE)) & "00";
                                            mxState                     <= MemXact_WriteByteToAddr;
                                        else
                                            if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                                WB_DAT_O                <= (others => 'X');
                                                case mxFifo(to_integer(mxFifoReadIdx)).addr(1 downto 0) is
                                                    when "00" =>
                                                        WB_SEL_O        <= "1000";
                                                        WB_DAT_O(31 downto 24) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));
                                                    when "01" =>
                                                        WB_SEL_O        <= "0100";
                                                        WB_DAT_O(23 downto 16) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));
                                                    when     "10" =>
                                                        WB_SEL_O        <= "0010";
                                                        WB_DAT_O(15 downto 8) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));
                                                    when     "11" =>
                                                        WB_SEL_O        <= "0001";
                                                        WB_DAT_O(7 downto 0) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));
                                                end case;

                                                WB_ADR_O(ADDR_32BIT_RANGE)<= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                                WB_ADR_O(minAddrBit-1 downto 0)<= (others => '0');
                                                WB_WE_O                 <= '1';
                                                wbXactActive            <= '1';
                                            else
                                                MEM_ADDR(ADDR_BIT_RANGE)<= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_BIT_RANGE);
                                                MEM_WRITE_ENABLE        <= '1';
                                                MEM_DATA_OUT            <= X"000000" & mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0);
                                                MEM_WRITE_BYTE          <= '1';
                                            end if;
                                            mxFifoReadIdx               <= mxFifoReadIdx + 1;
                                            mxState                     <= MemXact_Idle;
                                            mxHoldCycles                <= 0;
mxHoldCycles                    <= 2;

                                            -- If the data write is to a cached location, update cache at same time.
                                            if cacheL2MxAddrInCache = '1' then
                                                cacheL2WriteAddr        <= unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(L2CACHE_BIT_RANGE));
                                                cacheL2WriteData        <= mxFifo(to_integer(mxFifoReadIdx)).data;

                                                -- Initiate a cache memory write.
                                                cacheL2WriteByte        <= '1';
                                                cacheL2Write            <= '1';
                                            end if;
                                        end if;
    
                                    -- To write a word, if hardware supports it, write out to the word aligned address with data in bits 15-0 otherwise
                                    -- we first read the 32bit word, update it and write it back.
                                    when MX_CMD_WRITEHWORDTOADDR =>
                                        -- If Hardware half-word write not implemented or it is a write to the Startup ROM we have to resort
                                        -- to a read-modify-write operation.
                                        if IMPL_HW_WORD_WRITE = false
                                        then
                                            if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                                wbXactActive            <= '1';
                                            else
                                                MEM_READ_ENABLE         <= '1';
                                            end if;
                                            cacheL2WriteAddr            <= unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(L2CACHE_32BIT_RANGE)) & "00";
                                            mxState                     <= MemXact_WriteHWordToAddr;
                                        else
                                            if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                                WB_DAT_O                <= (others => 'X');
                                                case mxFifo(to_integer(mxFifoReadIdx)).addr(1) is
                                                    when '0' =>
                                                        WB_SEL_O        <= "1100";
                                                        WB_DAT_O(31 downto 16) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(15 downto 0));
                                                    when '1' =>
                                                        WB_SEL_O        <= "0011";
                                                        WB_DAT_O(15 downto 0) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(15 downto 0));
                                                end case;
                                                WB_ADR_O(ADDR_32BIT_RANGE)<= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                                WB_ADR_O(minAddrBit-1 downto 0)<= (others => '0');
                                                WB_WE_O                 <= '1';
                                                wbXactActive            <= '1';
                                            else
                                                MEM_ADDR(ADDR_BIT_RANGE)<= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_16BIT_RANGE) & "0";
                                                MEM_WRITE_ENABLE        <= '1';
                                                MEM_DATA_OUT            <= X"0000" & mxFifo(to_integer(mxFifoReadIdx)).data(15 downto 0);
                                                MEM_WRITE_HWORD         <= '1';
                                            end if;
                                            mxFifoReadIdx               <= mxFifoReadIdx + 1;
                                            mxState                     <= MemXact_Idle;

                                            -- If the data write is to a cached location, update cache at same time.
                                            if cacheL2MxAddrInCache = '1' then
                                                cacheL2WriteAddr        <= unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(L2CACHE_BIT_RANGE));
                                                cacheL2WriteData        <= mxFifo(to_integer(mxFifoReadIdx)).data;

                                                -- Initiate a cache memory write.
                                                cacheL2WriteHword       <= '1';
                                                cacheL2Write            <= '1';
                                            end if;
                                            mxHoldCycles                <= 0;
mxHoldCycles                    <= 2;
                                        end if;
    
                                    when others =>
                                        mxFifoReadIdx                   <= mxFifoReadIdx + 1;
                                        mxState                         <= MemXact_Idle;
                                end case;

                            -- If instruction queue is empty or there are no memory transactions to process and the instruction cache isnt full,
                            -- read the next instruction and fill the instruction cache.
                            elsif cacheL2Active = '1' and cacheL2Full = '0' and cacheL2IncAddr = '0' then
                                if IMPL_USE_WB_BUS = true and cacheL2FetchIdx(WB_SELECT_BIT) = '1' then
                                    WB_ADR_O(ADDR_32BIT_RANGE)          <= std_logic_vector(cacheL2FetchIdx(ADDR_32BIT_RANGE));
                                    WB_ADR_O(minAddrBit-1 downto 0)     <= (others => '0');
                                    WB_WE_O                             <= '0';
                                    WB_CYC_O                            <= '1';
                                    WB_STB_O                            <= '1';
                                    WB_CTI_O                            <= "000";
                                    WB_SEL_O                            <= "1111";
                                    wbXactActive                        <= '1';
                                    mxHoldCycles                        <= 1;
                                else
                                    MEM_ADDR(ADDR_32BIT_RANGE)          <= std_logic_vector(cacheL2FetchIdx(ADDR_32BIT_RANGE));
                                    MEM_ADDR(minAddrBit-1 downto 0)     <= (others => '0');
                                    MEM_READ_ENABLE                     <= '1';
                                    mxHoldCycles                        <= 1;
                                end if;
                                cacheL2WriteAddr                        <= cacheL2FetchIdx(L2CACHE_BIT_RANGE);
                                mxState                                 <= MemXact_OpcodeFetch;

                            -- If there are no memory transactions to complete, debugging is enabled and the debug outputter is active, read the memory location
                            -- according to the given index.
                            elsif DEBUG_CPU = true and (debugState /= Debug_Idle and debugState /= Debug_DumpL1 and debugState /= Debug_DumpL2 and debugState /= Debug_DumpMem) then
                                if IMPL_USE_WB_BUS = true and debugPC(WB_SELECT_BIT) = '1' then
                                    WB_ADR_O(ADDR_32BIT_RANGE)          <= std_logic_vector(debugPC(ADDR_32BIT_RANGE));
                                    WB_ADR_O(minAddrBit-1 downto 0)     <= (others => '0');
                                    WB_WE_O                             <= '0';
                                    WB_CYC_O                            <= '1';
                                    WB_STB_O                            <= '1';
                                    WB_CTI_O                            <= "000";
                                    WB_SEL_O                            <= "1111";
                                    wbXactActive                        <= '1';
                                    mxHoldCycles                        <= 1;
                                else
                                    MEM_ADDR(ADDR_32BIT_RANGE)          <= std_logic_vector(debugPC(ADDR_32BIT_RANGE));
                                    MEM_ADDR(minAddrBit-1 downto 0)     <= (others => '0');
                                    MEM_READ_ENABLE                     <= '1';
                                end if;
                                mxMemVal.valid                          <= '0';
                                mxState                                 <= MemXact_MemoryFetch;
                            end if;
    
                        when MemXact_MemoryFetch =>
                            if DEBUG_CPU = true then
                                if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                    mxMemVal.word                       <= unsigned(WB_DAT_I);
                                else
                                    mxMemVal.word                       <= unsigned(MEM_DATA_IN);
                                end if;
                                mxMemVal.valid                          <= '1';
                            end if;
                            mxState                                     <= MemXact_Idle;
    
                        when MemXact_OpcodeFetch =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                cacheL2WriteData                        <= WB_DAT_I;
                            else
                                cacheL2WriteData                        <= MEM_DATA_IN;
                            end if;

                            -- Initiate a cache memory write if there has been no change of PC.
                            if cacheL2WriteAddr = cacheL2FetchIdx(L2CACHE_BIT_RANGE) then
                                cacheL2Write                                <= '1';
                                cacheL2IncAddr                              <= '1';
                            end if;
                            mxState                                     <= MemXact_Idle;

                        when MemXact_TOS =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                mxTOS.word                              <= unsigned(WB_DAT_I);
                            else
                                mxTOS.word                              <= unsigned(MEM_DATA_IN);
                            end if;
                            mxTOS.valid                                 <= '1';
                            if cacheL2Active = '1' then
                                mxHoldCycles                            <= 1;
                            end if;
                            mxState                                     <= MemXact_Idle;
    
                        when MemXact_NOS =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                mxNOS.word                              <= unsigned(WB_DAT_I);
                            else
                                mxNOS.word                              <= unsigned(MEM_DATA_IN);
                            end if;
                            mxNOS.valid                                 <= '1';
                            if cacheL2Active = '1' then
                                mxHoldCycles                            <= 1;
                            end if;
                            mxState                                     <= MemXact_Idle;
    
                        when MemXact_TOSNOS =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                mxTOS.word                              <= unsigned(WB_DAT_I);
                            else
                                mxTOS.word                              <= unsigned(MEM_DATA_IN);
                                MEM_ADDR(ADDR_32BIT_RANGE)              <= std_logic_vector(to_unsigned(to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE))) + 1, ADDR_32BIT_SIZE));
                                MEM_ADDR(minAddrBit-1 downto 0)         <= (others => '0');
                                MEM_READ_ENABLE                         <= '1';
                                mxHoldCycles                            <= 1;
                            end if;
                            mxTOS.valid                                 <= '1';
                            mxState                                     <= MemXact_TOSNOS_2;
    
                        when MemXact_TOSNOS_2 =>
                            if IMPL_USE_WB_BUS = true and mxFifo(to_integer(mxFifoReadIdx)).addr(WB_SELECT_BIT) = '1' then
                                WB_ADR_O(ADDR_32BIT_RANGE)              <= std_logic_vector(to_unsigned(to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE))) + 1, ADDR_32BIT_SIZE));
                                WB_ADR_O(minAddrBit-1 downto 0)         <= (others => '0');
                                WB_WE_O                                 <= '0';
                                WB_CYC_O                                <= '1';
                                WB_STB_O                                <= '1';
                                WB_SEL_O                                <= "1111";
                                wbXactActive                            <= '1';
                                mxState                                 <= MemXact_TOSNOS_3;
                            else
                                mxNOS.word                              <= unsigned(MEM_DATA_IN);
                                mxNOS.valid                             <= '1';
                                mxFifoReadIdx                           <= mxFifoReadIdx + 1;
                                mxState                                 <= MemXact_Idle;
                            end if;
                            if cacheL2Active = '1' then
                                mxHoldCycles                            <= 1;
                            end if;

                        when MemXact_TOSNOS_3 =>
                            if IMPL_USE_WB_BUS = true and wbXactActive  = '1' then
                                mxNOS.word                              <= unsigned(WB_DAT_I);
                                mxNOS.valid                             <= '1';
                                mxFifoReadIdx                           <= mxFifoReadIdx + 1;
                                mxState                                 <= MemXact_Idle;
                            end if;
    
                        when MemXact_ReadByteToTOS =>
                            mxTOS.word                                  <= (others => '0');
                            if wbXactActive   = '1' then
                                mxTOS.word(7 downto 0)                  <= unsigned(WB_DAT_I(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8));
                            else
                                mxTOS.word(7 downto 0)                  <= unsigned(MEM_DATA_IN(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8));
                            end if;
                            mxTOS.valid                                 <= '1';
                            mxFifoReadIdx                               <= mxFifoReadIdx + 1;
                            mxState                                     <= MemXact_Idle;
    
                        when MemXact_ReadWordToTOS =>
                            mxTOS.word                                  <= (others => '0');
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                mxTOS.word(15 downto 0)                 <= unsigned(WB_DAT_I(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16));
                            else
                                mxTOS.word(15 downto 0)                 <= unsigned(MEM_DATA_IN(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16));
                            end if;
                            mxTOS.valid                                 <= '1';
                            mxFifoReadIdx                               <= mxFifoReadIdx + 1;
                            mxState                                     <= MemXact_Idle;
    
                        when MemXact_ReadAddToTOS =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                mxTOS.word                              <= muxTOS.word + unsigned(WB_DAT_I);
                            else
                                mxTOS.word                              <= muxTOS.word + unsigned(MEM_DATA_IN);
                            end if;
                            mxTOS.valid                                 <= '1';
                            mxState                                     <= MemXact_Idle;
    
                        when MemXact_WriteToAddr =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                WB_ADR_O(ADDR_32BIT_RANGE)              <= WB_DAT_I(ADDR_32BIT_RANGE);
                                WB_ADR_O(minAddrBit-1 downto 0)         <= (others => '0');
                                WB_DAT_O                                <= mxFifo(to_integer(mxFifoReadIdx)).data;
                                WB_WE_O                                 <= '1';
                                WB_CYC_O                                <= '1';
                                WB_STB_O                                <= '1';
                                WB_SEL_O                                <= "1111";
                                wbXactActive                            <= '1';
                                cacheL2WriteAddr                        <= unsigned(WB_DAT_I(L2CACHE_BIT_RANGE));
                            else
                                MEM_ADDR(ADDR_32BIT_RANGE)              <= MEM_DATA_IN(ADDR_32BIT_RANGE);
                                MEM_ADDR(minAddrBit-1 downto 0)         <= (others => '0');
                                MEM_DATA_OUT                            <= mxFifo(to_integer(mxFifoReadIdx)).data;
                                MEM_WRITE_ENABLE                        <= '1';
                                cacheL2WriteAddr                        <= unsigned(MEM_DATA_IN(L2CACHE_BIT_RANGE));
                            end if;

                            -- If the data write is to a cached location, update cache at same time.
                            if cacheL2MxAddrInCache = '1' then
                                cacheL2WriteData                        <= mxFifo(to_integer(mxFifoReadIdx)).data;

                                -- Initiate a cache memory write.
                                cacheL2Write                            <= '1';
                            end if;
                            mxFifoReadIdx                               <= mxFifoReadIdx + 1;
                            mxState                                     <= MemXact_Idle;
mxHoldCycles                    <= 2;
    
                        when MemXact_WriteByteToAddr =>
                            -- For wishbone, we need to store the data and terminate the current cycle before we can commence a write cycle.
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                WB_DAT_O                                <= WB_DAT_I;
                                WB_DAT_O(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));
                                cacheL2WriteData                        <= WB_DAT_I;
                                mxState                                 <= MemXact_WriteByteToAddr2;
                            else
                                MEM_ADDR(ADDR_32BIT_RANGE)              <= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                MEM_ADDR(minAddrBit-1 downto 0)         <= (others => '0');
                                MEM_DATA_OUT                            <= MEM_DATA_IN;
                                MEM_DATA_OUT(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));
                                MEM_WRITE_ENABLE                        <= '1';
                                cacheL2WriteData                        <= MEM_DATA_IN;
                                mxFifoReadIdx                           <= mxFifoReadIdx + 1;
                                mxState                                 <= MemXact_Idle;
                            end if;
                            -- If the data write is to a cached location, we have read the original value, so update cache with modified version.
                            if cacheL2MxAddrInCache = '1' then
                                -- Update the data to write with the actual changed byte,
                                cacheL2WriteData(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 0))))*8) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(7 downto 0));

                                -- Initiate a cache memory write.
                                cacheL2Write                            <= '1';
                            end if;
mxHoldCycles                    <= 2;

                        when MemXact_WriteByteToAddr2 =>
                            if IMPL_USE_WB_BUS = true then
                                WB_ADR_O(ADDR_32BIT_RANGE)              <= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                WB_ADR_O(minAddrBit-1 downto 0)         <= (others => '0');
                                WB_WE_O                                 <= '1';
                                WB_CYC_O                                <= '1';
                                WB_STB_O                                <= '1';
                                WB_SEL_O                                <= "1111";
                                wbXactActive                            <= '1';
                                mxFifoReadIdx                           <= mxFifoReadIdx + 1;
                                mxState                                 <= MemXact_Idle;
                            end if;
    
                        when MemXact_WriteHWordToAddr =>
                            if IMPL_USE_WB_BUS = true and wbXactActive   = '1' then
                                WB_DAT_O                                <= WB_DAT_I;
                                WB_DAT_O(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(15 downto 0));
                                cacheL2WriteData                        <= WB_DAT_I;
                                mxState                                 <= MemXact_WriteHWordToAddr2;
                            else
                                MEM_ADDR(ADDR_32BIT_RANGE)              <= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                MEM_ADDR(minAddrBit-1 downto 0)         <= (others => '0');
                                MEM_DATA_OUT                            <= MEM_DATA_IN;
                                MEM_DATA_OUT(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(15 downto 0));
                                cacheL2WriteData                        <= MEM_DATA_IN;
                                MEM_WRITE_ENABLE                        <= '1';
                                mxFifoReadIdx                           <= mxFifoReadIdx + 1;
                                mxState                                 <= MemXact_Idle;
                            end if;
                            -- If the data write is to a cached location, we have read the original value, so update cache with modified version.
                            if cacheL2MxAddrInCache = '1' then
                                -- Update the data to write with the actual changed byte,
                                cacheL2WriteData(((wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(mxFifo(to_integer(mxFifoReadIdx)).addr(byteBits-1 downto 1))))*16) <= std_logic_vector(mxFifo(to_integer(mxFifoReadIdx)).data(15 downto 0));

                                -- Initiate a cache memory write.
                                cacheL2Write                            <= '1';
                            end if;
mxHoldCycles                    <= 2;

                        when MemXact_WriteHWordToAddr2 =>
                            if IMPL_USE_WB_BUS = true then
                                WB_ADR_O(ADDR_32BIT_RANGE)              <= mxFifo(to_integer(mxFifoReadIdx)).addr(ADDR_32BIT_RANGE);
                                WB_ADR_O(minAddrBit-1 downto 0)         <= (others => '0');
                                WB_WE_O                                 <= '1';
                                WB_CYC_O                                <= '1';
                                WB_STB_O                                <= '1';
                                WB_SEL_O                                <= "1111";
                                wbXactActive                            <= '1';
                                mxFifoReadIdx                           <= mxFifoReadIdx + 1;
                                mxState                                 <= MemXact_Idle;
                            end if;
    
                        when others =>
                    end case;
                end if;
            end if;

            -- Instruction Level 2 cache, we read upto the limit then back off until the gap between executed and read instructions
            -- gets to a watermark and then re-enable reading. This allows the cache to maintain a set of past and future instructions so that when a
            -- branch or call occurs, there is a chance we already have the needed instructions in cache.
            --
            if cacheL2Active = '1' then

                -- If L2 fetching has been halted and the PC approaches the threshold (detault 3/4) then advance the Start Address of L2 data and re-enable L2 filling.
                if cacheL2FetchIdx(ADDR_32BIT_RANGE) > pc(ADDR_32BIT_RANGE) and pc(ADDR_32BIT_RANGE) > cacheL2StartAddr(ADDR_32BIT_RANGE) and (pc - cacheL2StartAddr) > ((MAX_L2CACHE_SIZE/4)*3) and cacheL2Full = '1' then
                    cacheL2StartAddr                            <= cacheL2StartAddr + 16;
                end if;

                -- If the PC goes out of scope of L2 data, reset and start fetching a fresh from the current PC address.
                -- We reset on a 64bit boundary as the L1 cache works on 64bit decoding.
                if cacheL2Invalid = '1' and cacheL2Empty = '0' then
                    cacheL2FetchIdx                             <= pc(ADDR_64BIT_RANGE) & "000";
                    cacheL2StartAddr                            <= pc(ADDR_64BIT_RANGE) & "000";
                    cacheL2Write                                <= '0';
                    cacheL2IncAddr                              <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- Use a mux to get the latest TOS/NOS values. This saves 1 clock cycle between data being retrieved and processed.
  muxTOS.valid <= mxTOS.valid or TOS.valid;
  muxTOS.word  <= mxTOS.word when mxTOS.valid = '1' else TOS.word;
  muxNOS.valid <= mxNOS.valid or NOS.valid;
  muxNOS.word  <= mxNOS.word when mxNOS.valid = '1' else NOS.word;
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------

    ------------------------------------------------------------------------------
    -- L1 Cache 
    --
    -- L1 cache is a very small closely coupled cache which holds a decoded 
    -- shadow copy of the L2 cache or the BRAM at the point of execution and a few
    -- instructions ahead. It is implemented in logic cells to allow instant
    -- random access. This is required to perform instruction optimisation such as
    -- multiple IM's and also to allow extended 2+ byte instructions which have
    -- almost zero penalty over 1 byte instructions.
    ------------------------------------------------------------------------------
    CACHE_LEVEL1: process(CLK, ZPURESET, pc)
        variable tOpcode                                 : std_logic_vector(OpCode_Size-1 downto 0);
        variable tDecodedOpcode                          : InsnType;
        variable tInsnOffset                             : unsigned(4 downto 0);
    begin

        ------------------------
        -- HIGH LEVEL         --
        ------------------------
    
        ------------------------
        -- ASYNCHRONOUS RESET --
        ------------------------
        if ZPURESET = '1' then
            cacheL1StartAddr                             <= (others => '0');
            cacheL1FetchIdx                              <= (others => '0');
            l1State                                      <= State_PreSetAddr;
            MEM_READ_ENABLE_INSN                         <= '0';
            MEM_ADDR_INSN                                <= (others => DontCareValue);

        ------------------------
        -- FALLING CLOCK EDGE --
        ------------------------
        elsif falling_edge(CLK) then

        -----------------------
        -- RISING CLOCK EDGE --
        -----------------------
        elsif rising_edge(CLK) then

            -- If the cache becomes invalid due to a change in the PC or no cached data available then resync.
            if (cacheL2Active = '1' and ((pc < cacheL2StartAddr or pc > cacheL2FetchIdx) and cacheL2StartAddr(ADDR_64BIT_RANGE) /= cacheL2FetchIdx(ADDR_64BIT_RANGE)))
               or 
               ((pc < cacheL1StartAddr or pc >= cacheL1FetchIdx) and cacheL1StartAddr(ADDR_64BIT_RANGE) /= cacheL1FetchIdx(ADDR_64BIT_RANGE)) 
               or
               l1State = State_PreSetAddr then

                -- RESYNC L1 Cache with BRAM/L2 Cache starting at current PC value..
                cacheL1FetchIdx                                                         <= pc(ADDR_64BIT_RANGE) & "000";
                cacheL1StartAddr                                                        <= pc(ADDR_64BIT_RANGE) & "000";

                -- For BRAM preset the next address.
                if cacheL2Active = '0' then
                    MEM_ADDR_INSN(ADDR_64BIT_RANGE)                                     <= std_logic_vector(pc(ADDR_64BIT_RANGE));
                    MEM_ADDR_INSN(minAddrBit downto 0)                                  <= (others => '0');
                    MEM_READ_ENABLE_INSN                                                <= '1';
                --else for L2 the address is automatically set in cacheL1FetchIdx
                end if;

                -- State machine goes directly to the latch address phase.
                l1State                                                                 <= State_LatchAddr;

            -- If there is space in the L1 cache and data is available in the L2 cache/BRAM and we are not outputting debug information, fetch the next word, decode and place in L1.
            elsif cacheL1Full = '0'
                  and
                  -- If instruction BRAM in use ensure the memory is ready, for L2 no need to wait as the pointers control the reading of L2 data.
                  ((cacheL2Active = '0' and MEM_BUSY_INSN = '0') or (cacheL2Active = '1'))
                  and
                  -- If using L2 cache then only process when cached data is available in L2.
                  (cacheL2Active = '0' or (cacheL2Active = '1' and cacheL2Empty = '0' and cacheL2FetchIdx(ADDR_64BIT_RANGE) > cacheL2StartAddr(ADDR_64BIT_RANGE)+1 and cacheL2FetchIdx(ADDR_64BIT_RANGE) > cacheL1FetchIdx(ADDR_64BIT_RANGE) and cacheL1StartAddr >= cacheL2StartAddr))
                  and
                  -- If debugging, only process if the debug FSM is idle as the L2 address is muxed with the debug address.
                  ((DEBUG_CPU = false or (DEBUG_CPU = true and debugState = Debug_Idle))) then

                case l1State is

                    -- This state gives time for the BRAM/L2 to latch the address ready for decode.
                    when State_LatchAddr =>
                        l1State                                                         <= State_Decode;

                    when State_Decode =>
                        -- Read cycle for BRAM is at least one clock, so on next cycle clear the BRAM read signal.
                        if cacheL2Active = '0' then
                            MEM_READ_ENABLE_INSN                                        <= '0';
                        -- else for L2 there is no distinct signal, always outputs data for given input address.
                        end if;

                        -- decode 8 instructions in parallel
                        for i in 0 to longWordBytes-1 loop
                            if cacheL2Active = '0' then
                                tOpcode                                                 := MEM_DATA_IN_INSN((longWordBytes-1-i+1)*8-1 downto (longWordBytes-1-i)*8);
                            else
                                tOpcode                                                 := cacheL2Word((longWordBytes-1-i+1)*8-1 downto (longWordBytes-1-i)*8);
                            end if;
        
                            tInsnOffset(4)                                              := not tOpcode(4);
                            tInsnOffset(3 downto 0)                                     := unsigned(tOpcode(3 downto 0));
        
                            if (tOpcode(7 downto 7) = OpCode_Im)         then tDecodedOpcode   := Insn_Im;
        
                            elsif (tOpcode(7 downto 5) = OpCode_StoreSP) then tDecodedOpcode   := Insn_StoreSP;
        
                            elsif (tOpcode(7 downto 5) = OpCode_LoadSP)  then tDecodedOpcode   := Insn_LoadSP;
        
                            -- Emulated instructions, if there is no defined state to handle the instruction in hardware then it automatically runs the instruction
                            -- microcode from the vector 0x0+xxxxx*32.
                            elsif (tOpcode(7 downto 5) = OpCode_Emulate) then tDecodedOpcode   := Insn_Emulate;
        
                                if                                     tOpcode(5 downto 0) = OpCode_Neqbranch        then tDecodedOpcode   := Insn_Neqbranch;
                                elsif                                  tOpcode(5 downto 0) = OpCode_Eqbranch         then tDecodedOpcode   := Insn_Eqbranch;
                                elsif IMPL_EQ = true               and tOpcode(5 downto 0) = OpCode_Eq               then tDecodedOpcode   := Insn_Eq;
                                elsif                                  tOpcode(5 downto 0) = OpCode_Lessthan         then tDecodedOpcode   := Insn_Lessthan;
                                elsif                                  tOpcode(5 downto 0) = OpCode_Lessthanorequal  then tDecodedOpcode   := Insn_Lessthanorequal;
                                elsif                                  tOpcode(5 downto 0) = OpCode_Ulessthan        then tDecodedOpcode   := Insn_Ulessthan;
                                elsif                                  tOpcode(5 downto 0) = OpCode_Ulessthanorequal then tDecodedOpcode   := Insn_Ulessthanorequal;
                                elsif IMPL_LOADB = true            and tOpcode(5 downto 0) = OpCode_Loadb            then tDecodedOpcode   := Insn_Loadb;
                                elsif IMPL_LOADH = true            and tOpcode(5 downto 0) = OpCode_Loadh            then tDecodedOpcode   := Insn_Loadh;
                                elsif IMPL_MULT = true             and tOpcode(5 downto 0) = OpCode_Mult             then tDecodedOpcode   := Insn_Mult;
                                elsif IMPL_STOREB = true           and tOpcode(5 downto 0) = OpCode_Storeb           then tDecodedOpcode   := Insn_Storeb;
                                elsif IMPL_STOREH = true           and tOpcode(5 downto 0) = OpCode_Storeh           then tDecodedOpcode   := Insn_Storeh;
                                elsif IMPL_PUSHSPADD = true        and tOpcode(5 downto 0) = OpCode_Pushspadd        then tDecodedOpcode   := Insn_Pushspadd;
                                elsif IMPL_CALLPCREL = true        and tOpcode(5 downto 0) = OpCode_Callpcrel        then tDecodedOpcode   := Insn_Callpcrel;
                                elsif IMPL_CALL = true             and tOpcode(5 downto 0) = OpCode_Call             then tDecodedOpcode   := Insn_Call;
                                elsif IMPL_SUB = true              and tOpcode(5 downto 0) = OpCode_Sub              then tDecodedOpcode   := Insn_Sub;
                                elsif IMPL_POPPCREL = true         and tOpcode(5 downto 0) = OpCode_PopPCRel         then tDecodedOpcode   := Insn_PopPCRel;
                                elsif IMPL_LSHIFTRIGHT = true      and tOpcode(5 downto 0) = OpCode_Lshiftright      then tDecodedOpcode   := Insn_Alshift;
                                elsif IMPL_ASHIFTLEFT = true       and tOpcode(5 downto 0) = OpCode_Ashiftleft       then tDecodedOpcode   := Insn_Alshift;
                                elsif IMPL_ASHIFTRIGHT = true      and tOpcode(5 downto 0) = OpCode_Ashiftright      then tDecodedOpcode   := Insn_Alshift;
                                elsif IMPL_XOR = true              and tOpcode(5 downto 0) = OpCode_Xor              then tDecodedOpcode   := Insn_Xor;
                                elsif IMPL_DIV = true              and tOpcode(5 downto 0) = OpCode_Div              then tDecodedOpcode   := Insn_Div;
                                elsif IMPL_MOD = true              and tOpcode(5 downto 0) = OpCode_Mod              then tDecodedOpcode   := Insn_Mod;
                                elsif IMPL_NEG = true              and tOpcode(5 downto 0) = OpCode_Neg              then tDecodedOpcode   := Insn_Neg;
                                elsif IMPL_NEQ = true              and tOpcode(5 downto 0) = OpCode_Neq              then tDecodedOpcode   := Insn_Neq;
                                elsif IMPL_FIADD32 = true          and tOpcode(5 downto 0) = OpCode_FiAdd32          then tDecodedOpcode   := Insn_FiAdd32;
                                elsif IMPL_FIDIV32 = true          and tOpcode(5 downto 0) = OpCode_FiDiv32          then tDecodedOpcode   := Insn_FiDiv32;
                                elsif IMPL_FIMULT32 = true         and tOpcode(5 downto 0) = OpCode_FiMult32         then tDecodedOpcode   := Insn_FiMult32;
        
                                end if;                                
        
                            elsif (tOpcode(7 downto 4) = OpCode_AddSP) then
                                if    tInsnOffset = 0             then tDecodedOpcode   := Insn_Shift;
                                elsif tInsnOffset = 1             then tDecodedOpcode   := Insn_AddTop;
                                else                                   tDecodedOpcode   := Insn_AddSP;
                                end if;
        
                            -- Extended multibyte instruction set. If the extend instruction is encountered then during the execution phase the lookahead mechanism is used to determine
                            -- the extended instruction and execute accordingly.
                            elsif IMPL_EXTENDED_INSN = true and tOpcode(3 downto 0) = Opcode_Extend then tDecodedOpcode  := Insn_Extend;
        
                            else
                                case tOpcode(3 downto 0) is
                                    when OpCode_Nop      =>            tDecodedOpcode   := Insn_Nop;
                                    when OpCode_PushSP   =>            tDecodedOpcode   := Insn_PushSP;
                                    when OpCode_PopPC    =>            tDecodedOpcode   := Insn_PopPC;
                                    when OpCode_Add      =>            tDecodedOpcode   := Insn_Add;
                                    when OpCode_Or       =>            tDecodedOpcode   := Insn_Or;
                                    when OpCode_And      =>            tDecodedOpcode   := Insn_And;
                                    when OpCode_Load     =>            tDecodedOpcode   := Insn_Load;
                                    when OpCode_Not      =>            tDecodedOpcode   := Insn_Not;
                                    when OpCode_Flip     =>            tDecodedOpcode   := Insn_Flip;
                                    when OpCode_Store    =>            tDecodedOpcode   := Insn_Store;
                                    when OpCode_PopSP    =>            tDecodedOpcode   := Insn_PopSP;
                                    when others          =>            tDecodedOpcode   := Insn_Break;
                                end case;
                            end if;
        
                            -- Store the decoded op directly into L1 cache.
                            cacheL1(to_integer(cacheL1FetchIdx+i))(DECODED_RANGE) <= std_logic_vector(to_unsigned(InsnType'POS(tDecodedOpcode), 6));
                            cacheL1(to_integer(cacheL1FetchIdx+i))(OPCODE_RANGE)  <= tOpcode;
                        end loop;

                        -- Set address for next read, via cacheL1FetchIdx for L2 and external signals for BRAM. NB cacheL1FetchIdx always points to the next 
                        -- available slot except during this state of the decoder.
                        cacheL1FetchIdx                                                 <= cacheL1FetchIdx + longWordBytes;

                        -- If we are not using L2 cache then take instructions direct from instruction BRAM. If a seperate
                        -- Instruction BRAM is not implemented, this will be ignored as L2 is our only source.
                        --
                        if cacheL2Active = '0' then
                            MEM_ADDR_INSN(ADDR_64BIT_RANGE)                             <= std_logic_vector(cacheL1FetchIdx(ADDR_64BIT_RANGE)+1);
                            MEM_ADDR_INSN(minAddrBit downto 0)                          <= (others => '0');
                            MEM_READ_ENABLE_INSN                                        <= '1';
                        --else for L2 the address is automatically set in cacheL1FetchIdx
                        end if;

                        -- Repeat the fetch and decode until the L1 cache is full then disable fetching until a space becomes available.
                        -- We halt just before the full mark because it takes one cycle to halt.
                        l1State                                                         <= State_LatchAddr;

                    when others =>
                        l1State                                                         <= State_PreSetAddr;
                end case;

            -- If there is only a set number of instructions remaining in the cache then we need to creep the start address forward so that
            -- more instructions are fetched and decoded. We do this to ensure as many past instructions are available for backward jumps which
            -- are most common in C. Adjust the threshold if forward jumps are more common.
            elsif cacheL1InsnAfterPC < 8 and cacheL1Full = '1' then
                cacheL1StartAddr                                                        <= cacheL1StartAddr + 8;
            end if;
        end if;
    end process;

    -- Description of signals:
    -- cacheL1StartAddr       Absolute Start Address of word in first cache location.
    -- cacheL1FetchIdx        Next location a decoded instruction set (4 instructions) will be written into.
    -- cacheL1InsnAfterPC     Number of instructions stored in cache forward of current PC. 
    -- cacheL1Empty           1 when cache is empty, 0 when valid data present.
    -- cacheL1Invalid         1 when cache doesnt have any valid instructions stored.
    -- cacheL1Full            1 when cache is full, 0 otherwise.
    --
    cacheL1InsnAfterPC                                   <= cacheL1FetchIdx - pc when (cacheL2Active = '0' or (cacheL2Active = '1' and cacheL2Invalid = '0')) and (pc >= cacheL1StartAddr and pc < cacheL1FetchIdx+4)
                                                            else to_unsigned(0, cacheL1InsnAfterPC'length);
    cacheL1Empty                                         <= '1'                  when cacheL1FetchIdx = cacheL1StartAddr
                                                            else '0';
 -- cacheL1Invalid                                       <= '0' when (cacheL2Active = '0' or (cacheL2Active = '1' and cacheL2Invalid = '0')) and pc(ADDR_32BIT_RANGE) >= cacheL1StartAddr(ADDR_32BIT_RANGE) and pc(ADDR_32BIT_RANGE) < cacheL1FetchIdx(ADDR_32BIT_RANGE)
 --                                                         else '1';
    cacheL1Full                                          <= '1'                  when (cacheL1FetchIdx - cacheL1StartAddr) = MAX_L1CACHE_SIZE
                                                            else '0';
    ------------------------------------------------------------------------------
    -- End of L1 Cache
    ------------------------------------------------------------------------------


    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Processor - Execution unit.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    PROCESSOR: process(CLK, ZPURESET, TOS, NOS, cacheL1, pc, sp, mxTOS, mxNOS, cacheL1FetchIdx, cacheL1StartAddr, cacheL2Active, cacheL2Empty, inBreak)
        variable tSpOffset                               : unsigned(4 downto 0);
        variable tIdx                                    : integer range 0 to 7;
        variable tInsnExec                               : std_logic;
        variable tShiftCnt                               : integer range 0 to 63;
    begin
        ------------------------
        -- HIGH LEVEL         --
        ------------------------
    
        -- Prepare general stack possibility addresses, ie. Popped, 2xPopped or Pushed.
        --
        incSp                                            <= sp + 1;
        incIncSp                                         <= sp + 2;
        decSp                                            <= sp - 1;
        incPC                                            <= pc + 1;
        incIncPC                                         <= pc + 2;
        inc3PC                                           <= pc + 3;
        inc4PC                                           <= pc + 4;
        inc5PC                                           <= pc + 5;

        ------------------------
        -- ASYNCHRONOUS RESET --
        ------------------------
        if ZPURESET = '1' then
            inBreak                                      <= '0';
            INT_ACK                                      <= '0';
            INT_DONE                                     <= '0';
            tIdx                                         := 0;
            tSpOffset                                    := (others => '0');
            state                                        <= State_Init;
            sp                                           <= to_unsigned(STACK_ADDR, maxAddrBit)(ADDR_32BIT_RANGE);
            pc                                           <= to_unsigned(RESET_ADDR_CPU, pc'LENGTH);
            idimFlag                                     <= '0';
            inInterrupt                                  <= '0';
            mxFifoWriteIdx                               <= (others => '0');
            interruptSuspendedAddr                       <= (others => '0');
            TOS                                          <= ((others => '0'), '0');
            NOS                                          <= ((others => '0'), '0');
            -- 
            if IMPL_DIV = true or IMPL_FIDIV32 = true or IMPL_MOD = true then
                divStart                                 <= '0';
                divQuotientFractional                    <= 0;
            end if;
            if IMPL_FIADD32 = true or IMPL_FIMULT32 = true then
                quotientFractional                       <= 15;
            end if;
            if DEBUG_CPU = true then
                debugRec                                 <= ZPU_DBG_T_INIT;
                debugLoad                                <= '0';
                debugState                               <= Debug_Idle;
                debugAllInfo                             <= '0';
                debugPC_StartAddr                        <= (others => '0');
                debugPC_EndAddr                          <= (others => '0');
                debugPC_Width                            <= 32;
                debugPC_WidthCounter                     <= 0;
                debugOutputOnce                          <= '0';
            else
                debugPC_StartAddr                        <= (others => DontCareValue);
                debugPC_EndAddr                          <= (others => DontCareValue);
                debugPC_Width                            <= 32;
                debugPC_WidthCounter                     <= 0;
                debugRec                                 <= ZPU_DBG_T_DONTCARE;
                debugLoad                                <= DontCareValue;
                debugReady                               <= DontCareValue;
                debugOutputOnce                          <= DontCareValue;
            end if;

        ------------------------
        -- FALLING CLOCK EDGE --
        ------------------------
        elsif falling_edge(CLK) then

        -----------------------
        -- RISING CLOCK EDGE --
        -----------------------
        elsif rising_edge(CLK) then

          -- Debug statement to output data, either All, L1 Cache, L2 Cache or a Memory block.
          --if DEBUG_CPU = true and debugState = Debug_Idle and pc = X"385e" then
          --    debugPC_StartAddr                                                       <= X"01fc00"; --to_unsigned(131072-(512*3),     debugPC_StartAddr'LENGTH);
          --    debugPC_EndAddr                                                         <= X"01ff00"; --to_unsigned(131072, debugPC_EndAddr'LENGTH);
          --    debugPC_Width                                                           <= 8;
          --    debugState                                                              <= Debug_DumpMem;
          --end if;

            -- Debug statement to output a block of data when a specific address is reached.
          --if DEBUG_CPU = true and debugState = Debug_Idle and pc = X"1002b67" then --cacheL1FetchIdx < cacheL1FetchIdx_last then
          --    debugState                                                              <= Debug_Start;
          --end if;

            -- In debug mode, the memory dump start and stop address are controlled by 2 vectors, preload them with defaults if uninitialised.
            if DEBUG_CPU = true and debugPC_EndAddr = 0 then
                debugPC_StartAddr                                                       <= to_unsigned(16#1000000#, debugPC_StartAddr'LENGTH);
                debugPC_EndAddr                                                         <= to_unsigned(16#1001000#, debugPC_EndAddr'LENGTH);
            end if;

            -- If the Memory Transaction processor has updated the stack parameters, update our working copy.
            --
            if mxTOS.valid = '1' then
                TOS.valid                                                               <= '1';
                TOS.word                                                                <= mxTOS.word;
            end if;
            if mxNOS.valid = '1' then
                NOS.valid                                                               <= '1';
                NOS.word                                                                <= mxNOS.word;
            end if;
      
            -- If debugging enabled, loading of debug information into the debug serialiser is only 1 clock width wide, reset on each clock tick.
            --
            if DEBUG_CPU = true then
                debugLoad                                                               <= '0';
            end if;
    
            -- Division start is only 1 clock width wide.
            if IMPL_DIV = true or IMPL_FIDIV32 = true or IMPL_MOD = true then
                divStart                                                                <= '0';
                divQuotientFractional                                                   <= 15;              -- Always reset the quotient, integer division sets to 0 as no fractional component.
            end if;
    
            -- If interrupt is active, we only clear the interrupt state once the PC is reset to the address which was suspended after the
            -- interrupt, this prevents recursive interrupt triggers, desirable in cetain circumstances but not for this current design.
            --
            if (INT_REQ = '1' or (IMPL_USE_WB_BUS = true and WB_INTA_I = '1')) and intTriggered = '0' then
                intTriggered                                                            <= '1';
            end if;
            INT_ACK                                                                     <= '0';             -- Reset interrupt acknowledge if set, width is 1 clock only.
            INT_DONE                                                                    <= '0';             -- Reset interrupt done if set, width is 1 clock only.
            if inInterrupt = '1' and pc(ADDR_BIT_RANGE) = interruptSuspendedAddr(ADDR_BIT_RANGE) then
                inInterrupt                                                             <= '0';             -- no longer in an interrupt
                INT_DONE                                                                <= '1';             -- Interrupt service routine complete.
            end if;
    
            -- BREAK signal follows internal signal on clock edge.
            BREAK                                                                       <= inBreak;

            -- Debug to output stack memory when we hit a given address.
            --if (pc >= X"00385d" and pc < X"00385f") and debugState = Debug_Idle then
            --    debugPC_StartAddr                                                       <= to_unsigned(16#001FC00#, debugPC_StartAddr'LENGTH);
            --    debugPC_EndAddr                                                         <= to_unsigned(16#001FFE0#, debugPC_EndAddr'LENGTH);
            --    debugPC_Width                                                           <= 32;
            --    debugState                                                              <= Debug_DumpMem;
            --end if;
    
            -------------------------------------
            -- Execution Processor.
            -------------------------------------
            if (DEBUG_CPU = false or (DEBUG_CPU = true and debugReady = '1')) then

                -- Only run the CPU if the debugger isnt in the debug FSM, the debugger has priority.
                --
                if (DEBUG_CPU = false or (DEBUG_CPU = true and debugState = Debug_Idle)) then
    
                    case state is
                        -- If the emulation cache is implemented, initialise it else startup the CPU.
                        when State_Init =>
                            state                                                           <= State_Idle;

                        -- Idle the CPU if ENABLE signal is low.
                        --
                        when State_Idle =>
                            if ENABLE = '1' then
                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)   <= std_logic_vector(sp);
                                mxFifo(to_integer(mxFifoWriteIdx)).cmd                      <= MX_CMD_READTOSNOS;
                                TOS.valid                                                   <= '0';
                                NOS.valid                                                   <= '0';
                                mxFifoWriteIdx                                              <= mxFifoWriteIdx + 1;
                                state                                                       <= State_Execute;

                                if DEBUG_CPU = true and DEBUG_LEVEL >= 4 and debugState = Debug_Idle then
                                    debugPC_StartAddr                                       <= to_unsigned(0,     debugPC_StartAddr'LENGTH);
                                    debugPC_EndAddr                                         <= to_unsigned(65536, debugPC_EndAddr'LENGTH);
                                    debugState                                              <= Debug_DumpMem;
                                end if;
                            end if;
    
                        -- Each instruction must:
                        --
                        -- 1. set idimFlag
                        -- 2. increase pc if applicable
                        -- 3. set next state if appliable, default back to State_Execute.
                        -- 4. do it's operation
                        when State_Execute =>

                            -- If the debug state machine is outputting data, hold off from further actions.
                            if DEBUG_CPU = true and debugState /= Debug_Idle then

                            -- When a break is active, all processing is suspended.
                            elsif inBreak = '1' then
                                
                                -- If continue flag set, resume with next instruction.
                                if CONTINUE = '1' then
                                    tInsnExec                                               := '1';
                                    idimFlag                                                <= '0';
                                    pc                                                      <= incPC;
                                    inBreak                                                 <= '0';
                                end if;

                            -- Act immediately if an interrupt has occurred. Do not recurse into ISR while interrupt line is active 
                            elsif intTriggered = '1' and inInterrupt = '0' and idimFlag = '0' then

                                -- We have to wait for TOS and NOS to become valid so they can be saved, so loop until they are valid.
                                if muxTOS.valid = '1' and muxNOS.valid = '1' then
                                    -- We got an interrupt, execute interrupt instead of next instruction
                                    intTriggered                                            <= '0';
                                    inInterrupt                                             <= '1';
                                    INT_ACK                                                 <= '1';                                           -- Acknowledge interrupt.
                                    interruptSuspendedAddr                                  <= pc(ADDR_BIT_RANGE);                            -- Save address which got interrupted.
                                  --TOS.word                                                <= (others => DontCareValue);
                                    TOS.word(ADDR_BIT_RANGE)                                <= pc;
                                    NOS.word                                                <= muxTOS.word;
                                    pc                                                      <= to_unsigned(32+START_ADDR_MEM, maxAddrBit);    -- Load Vector 0x20 (from memory start) as next address to execute from.
                                    sp                                                      <= decSp;
    
                                    -- Setup a memory transaction to save NOS back to RAM, TOS in effect already popped.
                                    mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incSp);
                                    mxFifo(to_integer(mxFifoWriteIdx)).data                 <= std_logic_vector(muxNOS.word);
                                    mxFifo(to_integer(mxFifoWriteIdx)).cmd                  <= MX_CMD_WRITE;
                                    mxFifoWriteIdx                                          <= mxFifoWriteIdx + 1;
    
                                    -- If debug enabled, write out state during fetch.
                                    if DEBUG_CPU = true and DEBUG_LEVEL >= 0 then
                                        debugRec.FMT_DATA_PRTMODE                           <= "00";
                                        debugRec.FMT_PRE_SPACE                              <= '0';
                                        debugRec.FMT_POST_SPACE                             <= '0';
                                        debugRec.FMT_PRE_CR                                 <= '1';
                                        debugRec.FMT_POST_CRLF                              <= '1';
                                        debugRec.FMT_SPLIT_DATA                             <= "00";
                                        debugRec.DATA_BYTECNT                               <= std_logic_vector(to_unsigned(6, 3));
                                        debugRec.DATA2_BYTECNT                              <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA3_BYTECNT                              <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA4_BYTECNT                              <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.WRITE_DATA                                 <= '1';
                                        debugRec.WRITE_DATA2                                <= '0';
                                        debugRec.WRITE_DATA3                                <= '0';
                                        debugRec.WRITE_DATA4                                <= '0';
                                        debugRec.WRITE_OPCODE                               <= '0';
                                        debugRec.WRITE_DECODED_OPCODE                       <= '0';
                                        debugRec.WRITE_PC                                   <= '1';
                                        debugRec.WRITE_SP                                   <= '1';
                                        debugRec.WRITE_STACK_TOS                            <= '1';
                                        debugRec.WRITE_STACK_NOS                            <= '1';
                                        debugRec.DATA                                       <= X"494D544552505400";
                                        debugRec.PC(ADDR_BIT_RANGE)                         <= std_logic_vector(pc);
                                        debugRec.SP(ADDR_32BIT_RANGE)                       <= std_logic_vector(sp);
                                        debugRec.STACK_TOS                                  <= std_logic_vector(muxTOS.word);
                                        debugRec.STACK_NOS                                  <= std_logic_vector(muxNOS.word);
                                        debugLoad                                           <= '1';
                                    end if;
                                end if;

                            -- If the CPU is externally disabled during processing, go to the Idle state and wait until it is re-enabled.
                            --
                            elsif ENABLE = '0' then
                                state                                                       <= State_Idle;

                            -- Execution depends on the L1 having decoded instructions stored at the current PC.
                            -- As a minimum the cache must be valid and that there is at least 1 instruction in the cache. The PC is 1 byte granularity, the cache pointers are 64bit word granularity.
                            elsif pc >= cacheL1StartAddr and pc < cacheL1FetchIdx and cacheL1StartAddr(ADDR_64BIT_RANGE) /= cacheL1FetchIdx(ADDR_64BIT_RANGE) then


                                -- Set the stack offset for current instruction from its opcode.
                                tSpOffset(4)                                                := not cacheL1(to_integer(pc))(4);
                                tSpOffset(3 downto 0)                                       := unsigned(cacheL1(to_integer(pc)))(3 downto 0);
                                tInsnExec                                                   := '0';
                                if DEBUG_CPU = true then
                                    debugOutputOnce                                         <= '0';
                                end if;
        
                                --------------------------------------------------------------------------------------------------------------
                                -- Start of Instruction Execution Case block - process the current instruction held in L1 Cache.
                                --------------------------------------------------------------------------------------------------------------
                                case InsnType'VAL(to_integer(unsigned(cacheL1(to_integer(pc))(DECODED_RANGE)))) is
    
                                    -- Immediate, store 7bit signed extended value into TOS. If this is the first Im then we set IDIM, if this is a subsequent Im following
                                    -- on from other Im's without gap, then we shift TOS 7 bits to left and add in the new value. NB. First Im, bit 6 of bits 6-0 is used to set
                                    -- all bits 31 downto 6 with the same value.
                                    -- An optimisation has been added where by if more than 1 Im are sequential and in the L1 cache, then the result is calculated in 1 cycle. If due
                                    -- to not enough cache data a > 1 Im is partially processed, ie. 3 Im out of 5, then the 3 are processed in 1 cycle and the remaining two in seperate
                                    -- cycles.
                                    when Insn_Im =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '1';
                                            pc                                              <= incPC;
                                            
                                            -- If this is the first Im (single or non-cached) or this is a multi Im instruction, save current TOS and build new TOS from Im.
                                            --
                                            if idimFlag = '0' then 
                                                -- As we are pushing a value, current TOS becomes NOS and we write back old NOS to memory.
                                                NOS.word                                    <= muxTOS.word;
                                                sp                                          <= decSp;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).data     <= std_logic_vector(muxNOS.word);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_WRITE;
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;

                                                -- All Im combinations sign extend the 7th bit of the first Im instruction then just overwrite the bits available.
                                                --if cacheL1(to_integer(pc))(6) = '1' then
                                                --    TOS.word                                <= "11111111111111111111111110000000";
                                                --else
                                                --    TOS.word                                <= (others => '0');
                                                --end if;
                                                for i in wordSize-1 downto 7 loop
                                                    TOS.word(i)                             <= cacheL1(to_integer(pc))(6);
                                                end loop;

                                                -- Debug code, if enabled, writes out the data relevant to the Im instruction being optimised.
                                                if DEBUG_CPU = true and DEBUG_LEVEL >= 5 and cacheL1FetchIdx(L1CACHE_BIT_RANGE) - pc(L1CACHE_BIT_RANGE) > 2 then
                                                    debugRec.FMT_DATA_PRTMODE               <= "01";
                                                    debugRec.FMT_PRE_SPACE                  <= '0';
                                                    debugRec.FMT_POST_SPACE                 <= '1';
                                                    debugRec.FMT_PRE_CR                     <= '1';
                                                    debugRec.FMT_POST_CRLF                  <= '1';
                                                    debugRec.FMT_SPLIT_DATA                 <= "11";
                                                    debugRec.DATA_BYTECNT                   <= std_logic_vector(to_unsigned(7, 3));
                                                    debugRec.DATA2_BYTECNT                  <= std_logic_vector(to_unsigned(7, 3));
                                                    debugRec.DATA3_BYTECNT                  <= std_logic_vector(to_unsigned(7, 3));
                                                    debugRec.DATA4_BYTECNT                  <= std_logic_vector(to_unsigned(7, 3));
                                                    debugRec.WRITE_DATA                     <= '1';
                                                    debugRec.WRITE_DATA2                    <= '1';
                                                    debugRec.WRITE_DATA3                    <= '1';
                                                    debugRec.WRITE_DATA4                    <= '1';
                                                    debugRec.WRITE_OPCODE                   <= '0';
                                                    debugRec.WRITE_DECODED_OPCODE           <= '0';
                                                    debugRec.WRITE_PC                       <= '1';
                                                    debugRec.WRITE_SP                       <= '1';
                                                    debugRec.WRITE_STACK_TOS                <= '1';
                                                    debugRec.WRITE_STACK_NOS                <= '1';
                                                    debugRec.DATA(63 downto 0)              <= "00" & cacheL1(to_integer(pc))(DECODED_RANGE) & cacheL1(to_integer(pc))(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+1)(DECODED_RANGE) & cacheL1(to_integer(pc)+1)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+2)(DECODED_RANGE) & cacheL1(to_integer(pc)+2)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+3)(DECODED_RANGE) & cacheL1(to_integer(pc)+3)(OPCODE_RANGE);
                                                    debugRec.DATA2(63 downto 0)             <= "00" & cacheL1(to_integer(pc)+4)(DECODED_RANGE) & cacheL1(to_integer(pc)+4)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+5)(DECODED_RANGE) & cacheL1(to_integer(pc)+5)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+6)(DECODED_RANGE) & cacheL1(to_integer(pc)+6)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+7)(DECODED_RANGE) & cacheL1(to_integer(pc)+7)(OPCODE_RANGE);
                                                    debugRec.DATA3(63 downto 0)             <= std_logic_vector(to_unsigned(to_integer(cacheL2FetchIdx), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1FetchIdx), 16))  & std_logic_vector(to_unsigned(to_integer(pc), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1StartAddr), 16));
                                                    debugRec.DATA4(63 downto 0)             <= "0000000000000000" & std_logic_vector(to_unsigned(to_integer(cacheL2StartAddr), 16)) & std_logic_vector(cacheL2FetchIdx(15 downto 0)) & "00" & cacheL1(to_integer(pc))(DECODED_RANGE) & "0000" & idimFlag & tInsnExec & cacheL2Full & cacheL2Write;
                                                    debugRec.OPCODE                         <= (others => DontCareValue);
                                                    debugRec.DECODED_OPCODE                 <= (others => DontCareValue);
                                                    debugRec.PC(ADDR_BIT_RANGE)             <= std_logic_vector(pc);
                                                    debugRec.SP(ADDR_32BIT_RANGE)           <= std_logic_vector(sp);
                                                    debugRec.STACK_TOS                      <= std_logic_vector(muxTOS.word);
                                                    debugRec.STACK_NOS                      <= std_logic_vector(muxNOS.word);
                                                    debugLoad                               <= '1';
                                                end if;


                                                -- For non-optimised hardware or optimised but we only have 1 Im, use the original logic.
                                                if IMPL_OPTIMIZE_IM = false then
                                                    TOS.word(IM_DATA_RANGE)                 <= unsigned(cacheL1(to_integer(pc))(IM_DATA_RANGE));
 
                                                -- If Im optimisation is enabled, work out if we have sufficient instructions and then determine how many Ims are grouped together, otherwise default to just 1 Im per time processing.
                                                elsif IMPL_OPTIMIZE_IM = true then

                                                    -- 5 Consecutive IM's
                                                    --if cacheL1FetchIdx - pc > 5    and cacheL1(to_integer(pc))(7) = '1' and cacheL1(to_integer(incPC))(7) = '1' and cacheL1(to_integer(incIncPC))(7) = '1' and cacheL1(to_integer(inc3PC))(7) = '1' and cacheL1(to_integer(inc4PC))(7) = '1' and cacheL1(to_integer(inc5PC))(7) = '0' then
                                                    if cacheL1InsnAfterPC > 5    and cacheL1(to_integer(pc))(7) = '1' and cacheL1(to_integer(incPC))(7) = '1' and cacheL1(to_integer(incIncPC))(7) = '1' and cacheL1(to_integer(inc3PC))(7) = '1' and cacheL1(to_integer(inc4PC))(7) = '1' and cacheL1(to_integer(inc5PC))(7) = '0' then
                                                        TOS.word(31 downto 0)               <= unsigned(cacheL1(to_integer(pc))(3 downto 0)) & unsigned(cacheL1(to_integer(incPC))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(incIncPC))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(inc3PC))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(inc4PC))(OPCODE_IM_RANGE));
                                                        pc                                  <= inc5PC;
                                                    -- 4 Consecutive IM's
                                                    --elsif cacheL1FetchIdx - pc > 4 and cacheL1(to_integer(pc))(7) = '1' and cacheL1(to_integer(incPC))(7) = '1' and cacheL1(to_integer(incIncPC))(7) = '1' and cacheL1(to_integer(inc3PC))(7) = '1' and cacheL1(to_integer(inc4PC))(7) = '0' then
                                                    elsif cacheL1InsnAfterPC > 4 and cacheL1(to_integer(pc))(7) = '1' and cacheL1(to_integer(incPC))(7) = '1' and cacheL1(to_integer(incIncPC))(7) = '1' and cacheL1(to_integer(inc3PC))(7) = '1' and cacheL1(to_integer(inc4PC))(7) = '0' then
                                                        TOS.word(27 downto 0)               <= unsigned(cacheL1(to_integer(pc))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(incPC))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(incIncPC))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(inc3PC))(OPCODE_IM_RANGE));
                                                        pc                                  <= inc4PC; 
                                                    -- 3 Consecutive IM's
                                                    elsif cacheL1InsnAfterPC > 3 and cacheL1(to_integer(pc))(7) = '1' and cacheL1(to_integer(incPC))(7) = '1' and cacheL1(to_integer(incIncPC))(7) = '1' and cacheL1(to_integer(inc3PC))(7) = '0' then
                                                        TOS.word(20 downto 0)               <= unsigned(cacheL1(to_integer(pc))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(incPC))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(incIncPC))(OPCODE_IM_RANGE));
                                                        pc                                  <= inc3PC;
                                                    -- 2 Consecutive IM's
                                                    elsif cacheL1InsnAfterPC > 2 and cacheL1(to_integer(pc))(7) = '1' and cacheL1(to_integer(incPC))(7) = '1' and cacheL1(to_integer(incIncPC))(7) = '0' then
                                                        TOS.word(13 downto 0)               <= unsigned(cacheL1(to_integer(pc))(OPCODE_IM_RANGE)) & unsigned(cacheL1(to_integer(incPC))(OPCODE_IM_RANGE));
                                                        pc                                  <= incIncPC;
                                                    -- 1 IM
                                                    else 
                                                        TOS.word(IM_DATA_RANGE)             <= unsigned(cacheL1(to_integer(pc))(OPCODE_RANGE)(IM_DATA_RANGE));
                                                    end if;
                                                end if;
                                            else
                                                -- Further single Im instructions shift left by 7 bits then add it the value from the current opcode.
                                                TOS.word(wordSize-1 downto 7)               <= muxTOS.word(wordSize-8 downto 0);
                                                TOS.word(IM_DATA_RANGE)                     <= unsigned(cacheL1(to_integer(pc))(OPCODE_IM_RANGE));
                                            end if;
                                        end if;
 
                                    -- Store into Stack pointer + offset, write out the value in TOS to the location pointed by Stack pointer plus any offset given in the opcode.
                                    when Insn_StoreSP =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 2 then
                                            tInsnExec                                       := '1';
                                            tIdx                                            := 0;
                                            idimFlag                                        <= '0';
                                            sp                                              <= incSp;
                                            pc                                              <= incPC;

                                            -- Debug statement to output current parameters. Use this block in instructions which arent yielding their intended behaviour so that analysis can be made.
                                            --if (pc >= X"00385d" and pc < X"00385f") and DEBUG_CPU = true then
                                            --    debugRec.FMT_DATA_PRTMODE                 <= "01";
                                            --    debugRec.FMT_PRE_SPACE                    <= '0';
                                            --    debugRec.FMT_POST_SPACE                   <= '1';
                                            --    debugRec.FMT_PRE_CR                       <= '1';
                                            --    debugRec.FMT_POST_CRLF                    <= '1';
                                            --    debugRec.FMT_SPLIT_DATA                   <= "11";
                                            --    debugRec.DATA_BYTECNT                     <= std_logic_vector(to_unsigned(7, 3));
                                            --    debugRec.DATA2_BYTECNT                    <= std_logic_vector(to_unsigned(7, 3));
                                            --    debugRec.DATA3_BYTECNT                    <= std_logic_vector(to_unsigned(7, 3));
                                            --    debugRec.DATA4_BYTECNT                    <= std_logic_vector(to_unsigned(7, 3));
                                            --    debugRec.WRITE_DATA                       <= '1';
                                            --    debugRec.WRITE_DATA2                      <= '1';
                                            --    debugRec.WRITE_DATA3                      <= '1';
                                            --    debugRec.WRITE_DATA4                      <= '1';
                                            --    debugRec.WRITE_OPCODE                     <= '1';
                                            --    debugRec.WRITE_DECODED_OPCODE             <= '1';
                                            --    debugRec.WRITE_PC                         <= '1';
                                            --    debugRec.WRITE_SP                         <= '1';
                                            --    debugRec.WRITE_STACK_TOS                  <= '1';
                                            --    debugRec.WRITE_STACK_NOS                  <= '1';
                                            --    debugRec.DATA(63 downto 0)                <= std_logic_vector(to_unsigned(to_integer(pc), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1FetchIdx), 16))  & std_logic_vector(to_unsigned(to_integer(cacheL1StartAddr), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1InsnAfterPC), 16));
                                            --    debugRec.DATA2(63 downto 0)               <= std_logic_vector(to_unsigned(to_integer(cacheL2FetchIdx), 24))  & std_logic_vector(to_unsigned(to_integer(cacheL2StartAddr), 24)) & "10000000" & '0' & cacheL2IncAddr & idimFlag & tInsnExec & cacheL2Full & cacheL2Active & cacheL2Empty & cacheL2Write;
                                            --    debugRec.DATA3(63 downto 0)               <= X"FFFFFFFF" & std_logic_vector(TOS.word); 
                                            --    debugRec.DATA4(63 downto 0)               <= X"FFFFFFFF" & std_logic_vector(NOS.word); 
                                            --    debugRec.OPCODE                           <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                            --    debugRec.DECODED_OPCODE                   <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                            --    debugRec.PC(ADDR_BIT_RANGE)               <= std_logic_vector(pc);
                                            --    debugRec.SP(ADDR_32BIT_RANGE)             <= std_logic_vector(sp);
                                            --    debugRec.STACK_TOS                        <= std_logic_vector(muxTOS.word);
                                            --    debugRec.STACK_NOS                        <= std_logic_vector(muxNOS.word);
                                            --    debugLoad                                 <= '1';
                                            --end if;
    
                                            -- Always need to read the new NOS location into NOS unless the offset is 2 when the location will be
                                            -- overwritten with TOS, so just use TOS.
                                            if tSpOffset /= 2 then
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).cmd <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                tIdx                                        := tIdx + 1;
                                            end if;
    
                                            -- Write value of TOS to the memory location sp + offset stored in opcode if offset not 0 or 1.
                                            --
                                            if tSpOffset >= 2 then
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).addr(ADDR_32BIT_RANGE)<= std_logic_vector(sp+tSpOffset);
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).data<= std_logic_vector(muxTOS.word);
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).cmd <= MX_CMD_WRITE;
                                                tIdx                                        := tIdx + 1;
                                            end if;
    
                                            case tSpOffset is
                                                -- If the offset is 0, we are writing into unused stack (as the stack pointer is incremented), so just assign
                                                -- NOS to TOS and read the new NOS.
                                                when "00000" =>
                                                    TOS.word                                <= muxNOS.word;
    
                                                -- If the offset is 1 then we do nothing as a write of TOS to SP+1 is the location of the new TOS, so TOS doesnt change.
                                                -- We read NOS though from the new location.
                                                when "00001" =>
    
                                                -- When offset is 2, TOS is written to the new NOS position in memory, so no point to reread, we just reuse TOS.
                                                --
                                                when "00010" =>
                                                    NOS.word                                <= muxTOS.word;
                                                    TOS.word                                <= muxNOS.word;
    
                                                -- All other cases TOS becomes NOS and we read the new NOS .
                                                --
                                                when others =>
                                                    TOS.word                                <= muxNOS.word;
                                            end case;
    
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + tIdx;
                                        end if;
    
                                    -- Load from Stack pointer + offset: save NOS onto stack (TOS is popped and no longer needed so we are not concerned), read into TOS
                                    -- the value pointed to by the SP + Offset. NOS becomes the old TOS as we virtually pushed the read value onto the stack.
                                    when Insn_LoadSP =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 2 then
                                            tInsnExec                                       := '1';
                                            tIdx                                            := 0;
                                            idimFlag                                        <= '0';
                                            sp                                              <= decSp;
                                            pc                                              <= incPC;

                                            -- Commit NOS to memory as we will refresh NOS from TOS.
                                            mxFifo(to_integer(mxFifoWriteIdx)+tIdx).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)+tIdx).data    <= std_logic_vector(muxNOS.word);
                                            mxFifo(to_integer(mxFifoWriteIdx)+tIdx).cmd     <= MX_CMD_WRITE;
                                            tIdx                                            := tIdx + 1;
    
                                            -- If the offset is 0 then we are duplicating TOS into NOS.
                                            if tSpOffset = 0 then
                                                NOS.word                                    <= muxTOS.word;
    
                                            -- If the offset is 1 then we are duplicating NOS into TOS.
                                            elsif tSpOffset = 1 then
                                                TOS.word                                    <= muxNOS.word;
                                                NOS.word                                    <= muxTOS.word;
    
                                            -- Else we read the value at Sp + Offset into TOS.
                                            else
                                                -- Read TOS from the location pointed to by SP + Offset.
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(sp+tSpOffset);
                                                mxFifo(to_integer(mxFifoWriteIdx)+tIdx).cmd <= MX_CMD_READTOS;
                                                TOS.valid                                   <= '0';
                                                tIdx                                        := tIdx + 1;
    
                                                -- NOS becomes TOS as we are pushing a new value onto the stack.
                                                NOS.word                                    <= muxTOS.word;
                                            end if;
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + tIdx;
                                        end if;
    
                                    -- Emulate. This is a dummy placeholder for instructions which have not been implemented in hardware. If an Opcode cannot be translated to
                                    -- a state machine state, it falls through to here, the NOS is saved back onto the stack, TOS is set to NOS and TOS takes on
                                    -- the next program counter value (ie. next instruction after the one which is not implemented). The Program counter is then set
                                    -- to the vector containing the microcode to implement the instruction and a jump is made to that location. When the microcode is complete it
                                    -- should set the Program counter to the value stored in TOS.
                                    when Insn_Emulate =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            sp                                              <= decSp;
                                          --TOS.word                                        <= (others => DontCareValue);
                                            TOS.word(ADDR_BIT_RANGE)                        <= incPC;
                                            NOS.word                                        <= muxTOS.word;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).data         <= std_logic_vector(muxNOS.word);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_WRITE;
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
    
                                            -- The emulate address is calculated by the opcode value left shifted 5 places. If the BRAM start address is not zero then this is added to ensure the
                                            -- emulation microcode is read form the BRAM:
                                            --        98 7654 3210
                                            -- 0000 00aa aaa0 0000
                                            pc                                              <= to_unsigned(to_integer(unsigned(cacheL1(to_integer(pc))(OPCODE_RANGE)(4 downto 0)) & "00000"), pc'LENGTH) + START_ADDR_MEM;
                                        end if;
    
                                    -- Call function relative to current PC value. The Program counter for the next instruction after this (ie. call return address) is stored in TOS
                                    -- and the Program counter is set to the value currently in TOS+PC (remember that assignments only occur at end of the cycle, so writing to TOS wont 
                                    -- actually happen until the moment we leave this cycle) and we start processing from the new Program counter location, or the called location.
                                    when Insn_Callpcrel =>
                                        if IMPL_CALLPCREL = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                              --TOS.word                                    <= (others => DontCareValue);
                                                TOS.word(ADDR_BIT_RANGE)                    <= incPC;
                                                pc                                          <= pc + muxTOS.word(ADDR_BIT_RANGE);
                                            end if;
                                        end if;
    
                                    -- Call function. Same as above except the PC is set to the value stored in TOS, not TOS+PC.
                                    when Insn_Call =>
                                        if IMPL_CALL = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                              --TOS.word                                    <= (others => DontCareValue);
                                                TOS.word(ADDR_BIT_RANGE)                    <= incPC;
                                                pc                                          <= muxTOS.word(ADDR_BIT_RANGE);
                                            end if;
                                        end if;
    
                                    -- Add value from location pointed to bye Stack Pointer. Setup to read the value stored at Stack pointer location + offset contained
                                    -- in the OpCode. We then forward to the next state which adds the value read to the value stored in TOS.
                                    when Insn_AddSP =>
                                        if muxTOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(sp+tSpOffset);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READADDTOTOS;
                                            TOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Push stack pointer. TOS is set to stack pointer value and old TOS value assigned to NOS. The current NOS value is written out
                                    -- onto the stack. In effect TOS = sp, NOS = TOS and NOS stored to NOS-1, we accomplish a push stack pointer onto the stack.
                                    when Insn_PushSP =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= decSp;
                                            TOS.word                                        <= (others => '0');
                                            TOS.word(ADDR_32BIT_RANGE)                      <= sp;
                                            NOS.word                                        <= muxTOS.word;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).data         <= std_logic_vector(muxNOS.word);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_WRITE;
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Pop the value on the stack into the Program counter. This is accomplished by setting the PC to the TOS value, then writing out the
                                    -- NOS value (because NOS and TOS are not normally stored, they are held in register) and performing a resync.
                                    when Insn_PopPC =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= muxTOS.word(ADDR_BIT_RANGE);
                                            sp                                              <= incSp;
                                            TOS.word                                        <= muxNOS.word;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Same as above except the program counter is added to the value in TOS before being assigned to the next program counter value.
                                    when Insn_PopPCRel =>
                                        if IMPL_POPPCREL = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= pc + muxTOS.word(ADDR_BIT_RANGE);
                                                sp                                          <= incSp;
                                                TOS.word                                    <= muxNOS.word;
    
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;
    
                                    -- Add NOS to TOS and store into TOS. NOS is then read from the stack.
                                    when Insn_Add =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= muxTOS.word + muxNOS.word;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Subtract NOS from TOS and store into TOS. NOS is then read from the stack.
                                    when Insn_Sub =>
                                        if IMPL_SUB = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                TOS.word                                    <= muxNOS.word - muxTOS.word;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;
    
                                    -- Perform a logical OR between TOS and NOS and store the result in TOS. We then retrieve the next stack value into NOS.
                                    when Insn_Or =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= muxTOS.word or muxNOS.word;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Perform a logical AND between TOS and NOS and store the result in TOS. We then retrieve the next stack value into NOS.
                                    when Insn_And =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= muxTOS.word and muxNOS.word;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Perform a Equal comparison between TOS and NOS and store 1 in TOS if equal otherwise 0. We then retrieve the next stack value into NOS.
                                    when Insn_Eq =>
                                        if IMPL_EQ = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                TOS.word                                    <= (others => '0');
                                                if (muxTOS.word = muxNOS.word) then
                                                    TOS.word(0)                             <= '1';
                                                end if;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;
    
                                    -- Perform an unsigned less than comparison between TOS and NOS and store 1 in TOS if equal otherwise 0. We then retrieve the next stack value into NOS.
                                    when Insn_Ulessthan =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= (others => '0');
                                            if (muxTOS.word < muxNOS.word) then
                                                TOS.word(0)                                 <= '1';
                                            end if;
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Perform an unsigned less than or equal comparison between TOS and NOS and store 1 in TOS if equal otherwise 0. We then retrieve the next
                                    -- stack value into NOS.
                                    when Insn_Ulessthanorequal =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= (others => '0');
                                            if (muxTOS.word <= muxNOS.word) then
                                                TOS.word(0)                                 <= '1';
                                            end if;
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Perform a signed less than comparison between TOS and NOS and store 1 in TOS if equal otherwise 0. We then retrieve the next stack value into NOS.
                                    when Insn_Lessthan =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= (others => '0');
                                            if (signed(muxTOS.word) < signed(muxNOS.word)) then
                                                TOS.word(0)                                 <= '1';
                                            end if;
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Perform a signed less than or equal comparison between TOS and NOS and store 1 in TOS if equal otherwise 0. We then retrieve the next
                                    -- stack value into NOS.
                                    when Insn_Lessthanorequal =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incSp;
                                            TOS.word                                        <= (others => '0');
                                            if (signed(muxTOS.word) <= signed(muxNOS.word)) then
                                                TOS.word(0)                                 <= '1';
                                            end if;
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READNOS;
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Load TOS (next cycle) with the value pointed to by TOS.
                                    when Insn_Load =>
                                        if muxTOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_BIT_RANGE)  <= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READTOS;
                                            TOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
        
                                    -- Write the NOS value to the memory location pointed by TOS.
                                    when Insn_Store =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 2 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= incIncSp;
    
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_BIT_RANGE)<= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                            mxFifo(to_integer(mxFifoWriteIdx)).data         <= std_logic_vector(muxNOS.word);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_WRITE;
                                            mxFifo(to_integer(mxFifoWriteIdx)+1).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)+1).cmd        <= MX_CMD_READTOSNOS;
                                            TOS.valid                                       <= '0';
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 2;
                                        end if;
    
                                    -- Write the NOS value into memory location pointed to by the current Stack Pointer - 1 (ie. next of stack),
                                    -- then set the Stack Pointer to the current TOS value.
                                    when Insn_PopSP =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 2 then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC;
                                            sp                                              <= muxTOS.word(ADDR_32BIT_RANGE);
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).data         <= std_logic_vector(muxNOS.word);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_WRITE;
                                            mxFifo(to_integer(mxFifoWriteIdx)+1).addr(ADDR_BIT_RANGE)  <= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                            mxFifo(to_integer(mxFifoWriteIdx)+1).cmd        <= MX_CMD_READTOSNOS;
                                            TOS.valid                                       <= '0';
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 2;
                                        end if;
    
                                    -- No operation, just waste time.
                                    when Insn_Nop =>    
                                        tInsnExec                                           := '1';
                                        idimFlag                                            <= '0';
                                        pc                                                  <= incPC;
    
                                    -- Negate the TOS value.
                                    when Insn_Not =>
                                        if muxTOS.valid = '1' then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC; 
                                        
                                            TOS.word                                        <= not muxTOS.word;
                                        end if;
    
                                    -- Reverse all the bits in the TOS.
                                    when Insn_Flip =>
                                        if muxTOS.valid = '1' then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC; 
                                        
                                            for i in 0 to wordSize-1 loop
                                                TOS.word(i)                                 <= muxTOS.word(wordSize-1-i);
                                            end loop;
                                        end if;
    
                                    -- Add the TOS and NOS together, store in the TOS.
                                    when Insn_AddTop =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC; 
                                        
                                            TOS.word                                        <= muxTOS.word + muxNOS.word;
                                        end if;
    
                                    -- Shift the TOS right 1 bit.
                                    when Insn_Shift =>
                                        if muxTOS.valid = '1' then
                                            tInsnExec                                       := '1';
                                            idimFlag                                        <= '0';
                                            pc                                              <= incPC; 
                                        
                                            TOS.word(wordSize-1 downto 1)                   <= muxTOS.word(wordSize-2 downto 0);
                                            TOS.word(0)                                     <= '0';
                                        end if;
    
                                    -- Add the TOS to the Stack Pointer and store in TOS. This is word aligned so bits 0 & 1 are zero.
                                    when Insn_Pushspadd =>
                                        if IMPL_PUSHSPADD = true then
                                            if muxTOS.valid = '1' then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC; 
                                        
                                                TOS.word                                    <= (others => '0');
                                                TOS.word(ADDR_32BIT_RANGE)                  <= muxTOS.word((maxAddrBit-1)-minAddrBit downto 0)+sp;
                                            end if;
                                        end if;
    
                                    -- If the NOS is not 0 (or 0 for Eq) then add the TOS to the Program Counter. As the address is not guaranteed to be sequential, resync to
                                    -- retrieve the new TOS / NOS (because they are both now invalid) and the new program instruction. If the NOS is 0 then just
                                    -- retrieve the new TOS / NOS.
                                    when Insn_Neqbranch | Insn_Eqbranch =>
                                        if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                            tInsnExec                                       := '1';
                                            -- branches are almost always taken as they form loops
                                            idimFlag                                        <= '0';
                                            sp                                              <= incIncSp;

                                            if (InsnType'VAL(to_integer(unsigned(cacheL1(to_integer(pc))(DECODED_RANGE)))) = Insn_Neqbranch and muxNOS.word /= 0) or (InsnType'VAL(to_integer(unsigned(cacheL1(to_integer(pc))(DECODED_RANGE)))) = Insn_Eqbranch and NOS.word = 0) then
                                                pc                                          <= pc + muxTOS.word(ADDR_BIT_RANGE);
                                            else
                                                pc                                          <= incPC;
                                            end if;

                                            -- need to fetch stack again.                
                                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                            mxFifo(to_integer(mxFifoWriteIdx)).cmd          <= MX_CMD_READTOSNOS;
                                            TOS.valid                                       <= '0';
                                            NOS.valid                                       <= '0';
                                            mxFifoWriteIdx                                  <= mxFifoWriteIdx + 1;
                                        end if;
    
                                    -- Set in motion a signed multiplication of the TOS * NOS.
                                    when Insn_Mult =>
                                        if IMPL_MULT = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                state                                       <= State_Mult2;
                                                multResult                                  <= muxTOS.word * muxNOS.word;
                                            end if;
                                        end if;
        
                                    -- Set in motion a signed division of the TOS / NOS.
                                    when Insn_Div =>
                                        if IMPL_DIV = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                divStart                                    <= '1';
                                                divQuotientFractional                       <= 0;
                                                state                                       <= State_Div2;
                                            end if;
                                        end if;

                                    -- Set in motion a fixed point addition of the TOS / NOS.
                                    when Insn_FiAdd32 =>
                                        if IMPL_FIADD32 = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                state                                       <= State_FiAdd2;
                                            end if;
                                        end if;

                                    -- Set in motion a fixed point division of the TOS / NOS.
                                    when Insn_FiDiv32 =>
                                        if IMPL_FIDIV32 = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                state                                       <= State_FiDiv2;
                                            end if;
                                        end if;

                                    -- Set in motion a fixed point multiplication of the TOS / NOS.
                                    when Insn_FiMult32 =>
                                        if IMPL_FIMULT32 = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                state                                       <= State_FiMult2;
                                            end if;
                                        end if;
        
                                    -- Read the aligned word pointed to by the TOS and then process in the next state to extract just the required byte.
                                    when Insn_Loadb =>
                                        if IMPL_LOADB = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_BIT_RANGE) <= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READBYTETOTOS;
                                                TOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;
    
                                    -- Read the aligned dword pointed to by the TOS and update just the one required byte,
                                    -- The loadb and storeb can be sped up by implementing hardware byte read/write.
                                    when Insn_Storeb =>
                                        if IMPL_STOREB = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 2 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incIncSp;
    
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READTOSNOS;
                                                TOS.valid                                   <= '0';
                                                NOS.valid                                   <= '0';
    
                                                mxFifo(to_integer(mxFifoWriteIdx)+1).addr(ADDR_BIT_RANGE)  <= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                                mxFifo(to_integer(mxFifoWriteIdx)+1).data   <= std_logic_vector(muxNOS.word);
                                                mxFifo(to_integer(mxFifoWriteIdx)+1).cmd    <= MX_CMD_WRITEBYTETOADDR;
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 2;
                                            end if;
                                        end if;
    
                                    -- Read the aligned dword pointed to by the TOS and then process in the next state to extract just the required word.
                                    when Insn_Loadh =>
                                        if IMPL_LOADH = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_BIT_RANGE) <= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READWORDTOTOS;
                                                TOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;
    
                                    -- Read the aligned dword pointed to by the TOS and update just the one required word,
                                    -- The loadb and storeb can be sped up by implementing hardware byte read/write.
                                    when Insn_Storeh =>
                                        if IMPL_STOREH = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 2 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incIncSp;
    
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)  <= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READTOSNOS;
                                                TOS.valid                                   <= '0';
                                                NOS.valid                                   <= '0';
    
                                                mxFifo(to_integer(mxFifoWriteIdx)+1).addr(ADDR_BIT_RANGE)  <= std_logic_vector(muxTOS.word(ADDR_BIT_RANGE));
                                                mxFifo(to_integer(mxFifoWriteIdx)+1).data   <= std_logic_vector(muxNOS.word);
                                                mxFifo(to_integer(mxFifoWriteIdx)+1).cmd    <= MX_CMD_WRITEHWORDTOADDR;
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 2;
                                            end if;
                                        end if;
    
                                    -- Perform an exclusive or of the TOS and NOS which is stored in TOS in the next state. NOS is read from the
                                    -- new location.
                                    when Insn_Xor =>
                                        if IMPL_XOR = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                TOS.word                                    <= muxNOS.word xor muxTOS.word;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;

                                    -- Perform a negation or inverse of the TOS.
                                    when Insn_Neg =>
                                        if IMPL_NEG = true then
                                            if muxTOS.valid = '1' then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                TOS.word                                    <= (not muxTOS.word) + 1;
                                            end if;
                                        end if;
    
                                    -- Perform a signed comparison of TOS v NOS, if they are not equal, set the result to 1 which is stored in TOS in the next state. NOS
                                    -- is read from the new memory location.
                                    when Insn_Neq =>
                                        if IMPL_NEQ = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                TOS.word                                    <= (others => '0');
                                                if (signed(muxTOS.word) /= signed(muxNOS.word)) then
                                                    TOS.word(0)                             <= '1';
                                                end if;
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE)<= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                            end if;
                                        end if;
    
                                    -- Perform a modulo of TOS v NOS and push to stack. TOS is set to the result and NOS is read from the new stack location.
                                    when Insn_Mod =>
                                        if IMPL_MOD = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                                                divStart                                    <= '1';
                                                divQuotientFractional                       <= 0;
                                                state                                       <= State_Mod2;
                                            end if;
                                        end if;
    
                                    -- Shift NOS left or right TOS times according to the instruction. The shifting is done by VHDL operators paying attention to
                                    -- shift left arithmetic where the sla operator doesnt give the normal results.
                                    when Insn_Alshift =>
                                        if IMPL_ASHIFTLEFT = true or IMPL_ASHIFTRIGHT = true or IMPL_LSHIFTRIGHT = true then
                                            if muxTOS.valid = '1' and muxNOS.valid = '1' and mxXactSlotsFree >= 1 then
                                                tInsnExec                                   := '1';
                                                idimFlag                                    <= '0';
                                                pc                                          <= incPC;
                                                sp                                          <= incSp;
                    
                                                -- Positions to shift stored in TOS.
                                                tShiftCnt := to_integer(unsigned(std_logic_vector(muxTOS.word(5 downto 0))));

                                                -- Logical Shift Right
                                                if cacheL1(to_integer(pc))(5 downto 0) = OpCode_Lshiftright then
                                                    if (tShiftCnt = 0) then
                                                        TOS.word                            <= muxNOS.word;
                                                    else
                                                        TOS.word                            <= shift_right(muxNOS.word, tShiftCnt);
                                                    end if;
                                             --           for i in 1 to 63 loop
                                             --               if tShiftCnt = i then
                                             --                   TOS.word                    <= shift_right(muxNOS.word, i);
                                             --               end if;
                                             --           end loop;
                                             --       end if;
                                                end if;

                                                -- Arithmetic Shift Right
                                                if cacheL1(to_integer(pc))(5 downto 0) = OpCode_Ashiftright then
                                                    if (tShiftCnt = 0) then -- ASR #32
                                                        TOS.word                            <= (others => std_logic(muxNOS.word(31)));
                                                    else
                                                        TOS.word                            <= unsigned(shift_right(signed(muxNOS.word), tShiftCnt));
                                                    end if;
                                           --             for i in 1 to 63 loop
                                           --                 if tShiftCnt = i then
                                           --                     TOS.word                    <= unsigned(shift_right(signed(muxNOS.word), i));
                                           --                 end if;
                                           --             end loop;
                                           --         end if;
                                                end if;

                                                -- Arithmetic Shift Left (NB. VHDL sla behaves in a non-standard way, it mirrors sra hence use of sll).
                                                if cacheL1(to_integer(pc))(5 downto 0) = OpCode_Ashiftleft then
                                                    if (tShiftCnt = 0) then
                                                        TOS.word                            <= muxNOS.word;
                                                    else
                                                        TOS.word                            <= unsigned(shift_left(signed(muxNOS.word), tShiftCnt));
                                                    end if;
                                             --           for i in 1 to 63 loop
                                             --               if tShiftCnt = i then
                                             --                   TOS.word                    <= unsigned(shift_left(signed(muxNOS.word), i));
                                             --               end if;
                                             --           end loop;
                                             --       end if;
                                                end if;

                                                -- Fetch new NOS value.
                                                mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incIncSp);
                                                mxFifo(to_integer(mxFifoWriteIdx)).cmd      <= MX_CMD_READNOS;
                                                NOS.valid                                   <= '0';
                                                mxFifoWriteIdx                              <= mxFifoWriteIdx + 1;
                                                state                                       <= State_Execute;
                                            end if;
                                        end if;

                                    -- The ZPU has an 8 bit instruction set which has few spare slots. This intruction allows extended multibyte additions to be coded and processed.
                                    -- The instructions are coded as: Extend,<new insn[7:2]+ParamSize[1:0]>,[<byte>,<byte>,<byte>,<byte>]
                                    --                                Where ParamSize = 00 - No parameter bytes
                                    --                                                  01 - 8 bit parameter
                                    --                                                  10 - 16 bit parameter
                                    --                                                  11 - 32 bit parameter
                                    -- Thus without any additional data fetches, new instructions have access to 3 parameters, TOS, NOS and the InsnParameter.            
                                    -- ie. To create an LDIR, Source=TOS, Dest=NOS and InsnParameter=Count
                                    when Insn_Extend =>
                                        -- Ensure L1 cache has sufficient data to process this instruction, otherwise wait until it does before decoding and executing.
                                        if cacheL1FetchIdx - pc > to_integer(unsigned(cacheL1(to_integer(pc)+1)(OPCODE_RANGE)(OPCODE_PARAM_RANGE)))+1 then
                                            tInsnExec                                       := '1';

                                            -- For instructions which use a parameter, build the value ready for use.
                                            -- TODO: This should be variables to meet the 1 cycle requirement or set during decode.
                                            case cacheL1(to_integer(pc)+1)(OPCODE_PARAM_RANGE) is
                                                when "00" => insnExParameter                <= X"00000000";
                                                when "01" => insnExParameter                <= X"000000" & unsigned(cacheL1(to_integer(pc)+2)(OPCODE_RANGE));
                                                when "10" => insnExParameter                <= X"0000" & unsigned(cacheL1(to_integer(pc)+2)(OPCODE_RANGE)) & unsigned(cacheL1(to_integer(pc)+3)(OPCODE_RANGE));
                                                when "11" => insnExParameter                <= unsigned(cacheL1(to_integer(pc)+2)(OPCODE_RANGE)) & unsigned(cacheL1(to_integer(pc)+3)(OPCODE_RANGE)) & unsigned(cacheL1(to_integer(pc)+4)(OPCODE_RANGE)) & unsigned(cacheL1(to_integer(pc)+5)(OPCODE_RANGE));
                                            end case;
    
                                            -- Decode the extended instruction at this point as we have access to 8 future instructions or bytes so can work out what is required and execute.
                                            -- 1:0 = 00 means an instruction which operates with a default, byte, half-word or word parameter. ie. Extend,<insn>,[<byte>,<byte>,<byte>,<byte>]
    
                                            -- Memory fill instruction. Fill memory starting at address in NOS with zero, 8 bit, 16 or 32 bit repeating value for TOS bytes.
                                            --if cacheL1(to_integer(pc)+1)(OPCODE_INSN_RANGE) = Opcode_Ex_Fill then
                                            --end if;
    
                                            -- Debug code, if enabled, writes out the current instruction.
                                            if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                                debugRec.FMT_DATA_PRTMODE                   <= "00";
                                                debugRec.FMT_PRE_SPACE                      <= '0';
                                                debugRec.FMT_POST_SPACE                     <= '0';
                                                debugRec.FMT_PRE_CR                         <= '1';
                                                debugRec.FMT_POST_CRLF                      <= '1';
                                                debugRec.FMT_SPLIT_DATA                     <= "00";
                                                debugRec.DATA_BYTECNT                       <= std_logic_vector(to_unsigned(5, 3));
                                                debugRec.DATA2_BYTECNT                      <= std_logic_vector(to_unsigned(0, 3));
                                                debugRec.DATA3_BYTECNT                      <= std_logic_vector(to_unsigned(0, 3));
                                                debugRec.DATA4_BYTECNT                      <= std_logic_vector(to_unsigned(0, 3));
                                                debugRec.WRITE_DATA                         <= '1';
                                                debugRec.WRITE_DATA2                        <= '0';
                                                debugRec.WRITE_DATA3                        <= '0';
                                                debugRec.WRITE_DATA4                        <= '0';
                                                debugRec.WRITE_OPCODE                       <= '1';
                                                debugRec.WRITE_DECODED_OPCODE               <= '1';
                                                debugRec.WRITE_PC                           <= '1';
                                                debugRec.WRITE_SP                           <= '1';
                                                debugRec.WRITE_STACK_TOS                    <= '1';
                                                debugRec.WRITE_STACK_NOS                    <= '1';
                                                debugRec.DATA                               <= X"455854454E440000";
                                                debugRec.OPCODE                             <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                                debugRec.DECODED_OPCODE                     <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                                debugRec.PC(ADDR_BIT_RANGE)                 <= std_logic_vector(pc);
                                                debugRec.SP(ADDR_32BIT_RANGE)               <= std_logic_vector(sp);
                                                debugRec.STACK_TOS                          <= std_logic_vector(muxTOS.word);
                                                debugRec.STACK_NOS                          <= std_logic_vector(muxNOS.word);
                                                debugLoad                                   <= '1';
                                            end if;
                                        end if;

                                    -- Breakpoint, this is not a nornal instruction and used by debuggers to suspend a program exection. At the moment
                                    -- this instuction sets the BREAK flag and just continues.
                                    when Insn_Break =>
                                        tInsnExec                                           := '1';
                                        report "Break instruction encountered" severity failure;
                                        inBreak                                             <= '1';
    
                                        -- Debug code, if ENABLEd, writes out the current instruction.
                                        if DEBUG_CPU = true and DEBUG_LEVEL >= 0 then
                                            debugRec.FMT_DATA_PRTMODE                       <= "00";
                                            debugRec.FMT_PRE_SPACE                          <= '0';
                                            debugRec.FMT_POST_SPACE                         <= '0';
                                            debugRec.FMT_PRE_CR                             <= '1';
                                            debugRec.FMT_POST_CRLF                          <= '1';
                                            debugRec.FMT_SPLIT_DATA                         <= "00";
                                            debugRec.DATA_BYTECNT                           <= std_logic_vector(to_unsigned(7, 3));
                                            debugRec.DATA2_BYTECNT                          <= std_logic_vector(to_unsigned(0, 3));
                                            debugRec.DATA3_BYTECNT                          <= std_logic_vector(to_unsigned(0, 3));
                                            debugRec.DATA4_BYTECNT                          <= std_logic_vector(to_unsigned(0, 3));
                                            debugRec.WRITE_DATA                             <= '1';
                                            debugRec.WRITE_DATA2                            <= '0';
                                            debugRec.WRITE_DATA3                            <= '0';
                                            debugRec.WRITE_DATA4                            <= '0';
                                            debugRec.WRITE_OPCODE                           <= '1';
                                            debugRec.WRITE_DECODED_OPCODE                   <= '1';
                                            debugRec.WRITE_PC                               <= '1';
                                            debugRec.WRITE_SP                               <= '1';
                                            debugRec.WRITE_STACK_TOS                        <= '1';
                                            debugRec.WRITE_STACK_NOS                        <= '1';
                                            debugRec.DATA                                   <= X"425245414B504E54";
                                            debugRec.OPCODE                                 <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                            debugRec.DECODED_OPCODE                         <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                            debugRec.PC(ADDR_BIT_RANGE)                     <= std_logic_vector(pc);
                                            debugRec.SP(ADDR_32BIT_RANGE)                   <= std_logic_vector(sp);
                                            debugRec.STACK_TOS                              <= std_logic_vector(muxTOS.word);
                                            debugRec.STACK_NOS                              <= std_logic_vector(muxNOS.word);
                                            debugLoad                                       <= '1';

                                            -- Dump out the L1, L2 and Memory for debugging.
                                            debugState                                      <= Debug_Start;
                                        end if;
    
                                    -- Should never get here, so if debugging enabled, report.
                                    when others =>
                                        sp                                                  <= (others => DontCareValue);
                                        report "Illegal instruction" severity failure;
                                        inBreak                                             <= '1';
    
                                        -- Debug code, if ENABLEd, writes out the current instruction.
                                        if DEBUG_CPU = true and DEBUG_LEVEL >= 0 then
                                            debugRec.FMT_DATA_PRTMODE                       <= "00";
                                            debugRec.FMT_PRE_SPACE                          <= '0';
                                            debugRec.FMT_POST_SPACE                         <= '0';
                                            debugRec.FMT_PRE_CR                             <= '1';
                                            debugRec.FMT_POST_CRLF                          <= '1';
                                            debugRec.FMT_SPLIT_DATA                         <= "00";
                                            debugRec.DATA_BYTECNT                           <= std_logic_vector(to_unsigned(6, 3));
                                            debugRec.DATA2_BYTECNT                          <= std_logic_vector(to_unsigned(0, 3));
                                            debugRec.DATA3_BYTECNT                          <= std_logic_vector(to_unsigned(0, 3));
                                            debugRec.DATA4_BYTECNT                          <= std_logic_vector(to_unsigned(0, 3));
                                            debugRec.WRITE_DATA                             <= '1';
                                            debugRec.WRITE_DATA2                            <= '0';
                                            debugRec.WRITE_DATA3                            <= '0';
                                            debugRec.WRITE_DATA4                            <= '0';
                                            debugRec.WRITE_OPCODE                           <= '1';
                                            debugRec.WRITE_DECODED_OPCODE                   <= '1';
                                            debugRec.WRITE_PC                               <= '1';
                                            debugRec.WRITE_SP                               <= '1';
                                            debugRec.WRITE_STACK_TOS                        <= '1';
                                            debugRec.WRITE_STACK_NOS                        <= '1';
                                            debugRec.DATA                                   <= X"494C4C4547414C00";
                                            debugRec.OPCODE                                 <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                            debugRec.DECODED_OPCODE                         <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                            debugRec.PC(ADDR_BIT_RANGE)                     <= std_logic_vector(pc);
                                            debugRec.SP(ADDR_32BIT_RANGE)                   <= std_logic_vector(sp);
                                            debugRec.STACK_TOS                              <= std_logic_vector(muxTOS.word);
                                            debugRec.STACK_NOS                              <= std_logic_vector(muxNOS.word);
                                            debugLoad                                       <= '1';
                                        end if;
                                end case;

                                -- During waits, if debug enabled, output state and dump the L1 cache.
                                if DEBUG_CPU = true and DEBUG_LEVEL >= 1 and (pc = X"1f00010") then
                                    if debugState = Debug_Idle then
                                        debugState                                      <= Debug_DumpL2;
                                    end if;
                                end if;

                                -- Debug code, if enabled, writes out the current instruction.
                                if (DEBUG_CPU = true and DEBUG_LEVEL >= 1) and tInsnExec = '1' and pc >= X"000000" then
                                    debugRec.FMT_DATA_PRTMODE                               <= "01";
                                    debugRec.FMT_PRE_SPACE                                  <= '0';
                                    debugRec.FMT_POST_SPACE                                 <= '1';
                                    debugRec.FMT_PRE_CR                                     <= '1';
                                    debugRec.FMT_POST_CRLF                                  <= '1';
                                    debugRec.FMT_SPLIT_DATA                                 <= "11";
                                    debugRec.DATA_BYTECNT                                   <= std_logic_vector(to_unsigned(7, 3));
                                    debugRec.DATA2_BYTECNT                                  <= std_logic_vector(to_unsigned(7, 3));
                                    debugRec.DATA3_BYTECNT                                  <= std_logic_vector(to_unsigned(7, 3));
                                    debugRec.DATA4_BYTECNT                                  <= std_logic_vector(to_unsigned(7, 3));
                                    debugRec.WRITE_DATA                                     <= '1';
                                    debugRec.WRITE_DATA2                                    <= '1';
                                    debugRec.WRITE_DATA3                                    <= '1';
                                    debugRec.WRITE_DATA4                                    <= '1';
                                    debugRec.WRITE_OPCODE                                   <= '1';
                                    debugRec.WRITE_DECODED_OPCODE                           <= '1';
                                    debugRec.WRITE_PC                                       <= '1';
                                    debugRec.WRITE_SP                                       <= '1';
                                    debugRec.WRITE_STACK_TOS                                <= '1';
                                    debugRec.WRITE_STACK_NOS                                <= '1';
                                    debugRec.DATA(63 downto 0)                              <= std_logic_vector(to_unsigned(to_integer(pc), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1FetchIdx), 16))  & std_logic_vector(to_unsigned(to_integer(cacheL1StartAddr), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1InsnAfterPC), 16));
                                    debugRec.DATA2(63 downto 0)                             <= std_logic_vector(to_unsigned(to_integer(cacheL2FetchIdx), 24))  & std_logic_vector(to_unsigned(to_integer(cacheL2StartAddr), 24)) & "10000000" & '0' & cacheL2IncAddr & idimFlag & tInsnExec & cacheL2Full & cacheL2Active & cacheL2Empty & cacheL2Write;
                                    debugRec.DATA3(63 downto 0)                             <= "00" & cacheL1(to_integer(pc))(DECODED_RANGE)   & cacheL1(to_integer(pc))(OPCODE_RANGE)   & "00" & cacheL1(to_integer(pc)+1)(DECODED_RANGE) & cacheL1(to_integer(pc)+1)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+2)(DECODED_RANGE) & cacheL1(to_integer(pc)+2)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+3)(DECODED_RANGE) & cacheL1(to_integer(pc)+3)(OPCODE_RANGE);
                                    debugRec.DATA4(63 downto 0)                             <= "00" & cacheL1(to_integer(pc)+4)(DECODED_RANGE) & cacheL1(to_integer(pc)+4)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+5)(DECODED_RANGE) & cacheL1(to_integer(pc)+5)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+6)(DECODED_RANGE) & cacheL1(to_integer(pc)+6)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+7)(DECODED_RANGE) & cacheL1(to_integer(pc)+7)(OPCODE_RANGE);
                                  --debugRec.DATA4(63 downto 0)                             <= X"000" & std_logic_vector(mxXactSlotsFree) & X"000" & std_logic_vector(mxXactSlotsUsed) & X"000" & std_logic_vector(mxFifoWriteIdx) & X"000" & std_logic_vector(mxFifoReadIdx);
                                    debugRec.OPCODE                                         <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                    debugRec.DECODED_OPCODE                                 <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                    debugRec.PC(ADDR_BIT_RANGE)                             <= std_logic_vector(pc);
                                    debugRec.SP(ADDR_32BIT_RANGE)                           <= std_logic_vector(sp);
                                    debugRec.STACK_TOS                                      <= std_logic_vector(muxTOS.word);
                                    debugRec.STACK_NOS                                      <= std_logic_vector(muxNOS.word);
                                    debugLoad                                               <= '1';
                                end if;
                            else
                                if DEBUG_CPU = true and debugOutputOnce = '0' then
                                    -- During waits, if debug enabled, output state and dump the L1 cache.
                                    if DEBUG_CPU = true and DEBUG_LEVEL >= 1 and (pc = X"1002b67") then
                                        if debugState = Debug_Idle then
                                            debugState                                      <= Debug_DumpL2;
                                        end if;
                                    end if;
                                    if (DEBUG_CPU = true and DEBUG_LEVEL >= 1) and pc >= X"000000" then
                                        debugRec.FMT_DATA_PRTMODE                           <= "01";
                                        debugRec.FMT_PRE_SPACE                              <= '0';
                                        debugRec.FMT_POST_SPACE                             <= '1';
                                        debugRec.FMT_PRE_CR                                 <= '1';
                                        debugRec.FMT_POST_CRLF                              <= '1';
                                        debugRec.FMT_SPLIT_DATA                             <= "11";
                                        debugRec.DATA_BYTECNT                               <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.DATA2_BYTECNT                              <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.DATA3_BYTECNT                              <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.DATA4_BYTECNT                              <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.WRITE_DATA                                 <= '1';
                                        debugRec.WRITE_DATA2                                <= '1';
                                        debugRec.WRITE_DATA3                                <= '1';
                                        debugRec.WRITE_DATA4                                <= '1';
                                        debugRec.WRITE_OPCODE                               <= '1';
                                        debugRec.WRITE_DECODED_OPCODE                       <= '1';
                                        debugRec.WRITE_PC                                   <= '1';
                                        debugRec.WRITE_SP                                   <= '1';
                                        debugRec.WRITE_STACK_TOS                            <= '1';
                                        debugRec.WRITE_STACK_NOS                            <= '1';
                                        debugRec.DATA(63 downto 0)                          <= std_logic_vector(to_unsigned(to_integer(pc), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1FetchIdx), 16))  & std_logic_vector(to_unsigned(to_integer(cacheL1StartAddr), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1InsnAfterPC), 16));
                                        debugRec.DATA2(63 downto 0)                         <= std_logic_vector(to_unsigned(to_integer(cacheL2FetchIdx), 24))  & std_logic_vector(to_unsigned(to_integer(cacheL2StartAddr), 24)) & "00000000" & '0' & cacheL2IncAddr & idimFlag & tInsnExec & cacheL2Full & cacheL2Active & cacheL2Empty & cacheL2Write;
                                        debugRec.DATA3(63 downto 0)                         <= "00" & cacheL1(to_integer(pc))(DECODED_RANGE)   & cacheL1(to_integer(pc))(OPCODE_RANGE)   & "00" & cacheL1(to_integer(pc)+1)(DECODED_RANGE) & cacheL1(to_integer(pc)+1)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+2)(DECODED_RANGE) & cacheL1(to_integer(pc)+2)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+3)(DECODED_RANGE) & cacheL1(to_integer(pc)+3)(OPCODE_RANGE);
                                        debugRec.DATA4(63 downto 0)                         <= "00" & cacheL1(to_integer(pc)+4)(DECODED_RANGE) & cacheL1(to_integer(pc)+4)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+5)(DECODED_RANGE) & cacheL1(to_integer(pc)+5)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+6)(DECODED_RANGE) & cacheL1(to_integer(pc)+6)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+7)(DECODED_RANGE) & cacheL1(to_integer(pc)+7)(OPCODE_RANGE);
                                        debugRec.OPCODE                                     <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                        debugRec.DECODED_OPCODE                             <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                        debugRec.PC(ADDR_BIT_RANGE)                         <= std_logic_vector(pc);
                                        debugRec.SP(ADDR_32BIT_RANGE)                       <= std_logic_vector(sp);
                                        debugRec.STACK_TOS                                  <= std_logic_vector(muxTOS.word);
                                        debugRec.STACK_NOS                                  <= std_logic_vector(muxNOS.word);
                                        debugLoad                                           <= '1';
                                    end if;
                                    debugOutputOnce                                         <= '1';
                                end if;
                            end if; 

                            --------------------------------------------------------------------------------------------------------------
                            -- End of Instruction Execution Case block.
                            --------------------------------------------------------------------------------------------------------------

                        when State_Mult2 =>
                            if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                debugRec.FMT_DATA_PRTMODE                     <= "01";
                                debugRec.FMT_PRE_SPACE                        <= '0';
                                debugRec.FMT_POST_SPACE                       <= '1';
                                debugRec.FMT_PRE_CR                           <= '1';
                                debugRec.FMT_POST_CRLF                        <= '1';
                                debugRec.FMT_SPLIT_DATA                       <= "00";
                                debugRec.DATA_BYTECNT                         <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA2_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.DATA3_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.DATA4_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.WRITE_DATA                           <= '1';
                                debugRec.WRITE_DATA2                          <= '0';
                                debugRec.WRITE_DATA3                          <= '0';
                                debugRec.WRITE_DATA4                          <= '0';
                                debugRec.WRITE_OPCODE                         <= '1';
                                debugRec.WRITE_DECODED_OPCODE                 <= '1';
                                debugRec.WRITE_PC                             <= '1';
                                debugRec.WRITE_SP                             <= '1';
                                debugRec.WRITE_STACK_TOS                      <= '1';
                                debugRec.WRITE_STACK_NOS                      <= '1';
                                debugRec.DATA(63 downto 0)                    <= std_logic_vector(multResult);
                                debugRec.OPCODE                               <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                debugRec.DECODED_OPCODE                       <= std_logic_vector(to_unsigned(InsnType'POS(InsnType'VAL(to_integer(unsigned(cacheL1(to_integer(pc))(DECODED_RANGE))))) , 6));
                                debugRec.PC(ADDR_BIT_RANGE)                   <= std_logic_vector(pc);
                                debugRec.SP(ADDR_32BIT_RANGE)                 <= std_logic_vector(sp);
                                debugRec.STACK_TOS                            <= std_logic_vector(muxTOS.word);
                                debugRec.STACK_NOS                            <= std_logic_vector(muxNOS.word);
                                debugLoad                                     <= '1';
                            end if;

                            TOS.word                                          <= multResult(wordSize-1 downto 0);
                            mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incSp);
                            mxFifo(to_integer(mxFifoWriteIdx)).cmd            <= MX_CMD_READNOS;
                            NOS.valid                                         <= '0';
                            mxFifoWriteIdx                                    <= mxFifoWriteIdx + 1;
                            state                                             <= State_Execute;

                        when State_Div2 =>
                            if IMPL_DIV = true then
                                if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                    debugRec.FMT_DATA_PRTMODE                 <= "01";
                                    debugRec.FMT_PRE_SPACE                    <= '0';
                                    debugRec.FMT_POST_SPACE                   <= '1';
                                    debugRec.FMT_PRE_CR                       <= '1';
                                    debugRec.FMT_POST_CRLF                    <= '1';
                                    debugRec.FMT_SPLIT_DATA                   <= "00";
                                    debugRec.DATA_BYTECNT                     <= std_logic_vector(to_unsigned(7, 3));
                                    debugRec.DATA2_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA3_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA4_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.WRITE_DATA                       <= '1';
                                    debugRec.WRITE_DATA2                      <= '0';
                                    debugRec.WRITE_DATA3                      <= '0';
                                    debugRec.WRITE_DATA4                      <= '0';
                                    debugRec.WRITE_OPCODE                     <= '1';
                                    debugRec.WRITE_DECODED_OPCODE             <= '1';
                                    debugRec.WRITE_PC                         <= '1';
                                    debugRec.WRITE_SP                         <= '1';
                                    debugRec.WRITE_STACK_TOS                  <= '1';
                                    debugRec.WRITE_STACK_NOS                  <= '1';
                                    debugRec.DATA(63 downto 0)                <= "00" & std_logic_vector(divisorCopy(61 downto 0));
                                    debugRec.OPCODE                           <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                    debugRec.DECODED_OPCODE                   <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                    debugRec.PC(ADDR_BIT_RANGE)               <= std_logic_vector(pc);
                                    debugRec.SP(ADDR_32BIT_RANGE)             <= std_logic_vector(sp);
                                    debugRec.STACK_TOS                        <= dividendCopy(31 downto 0);
                                    debugRec.STACK_NOS                        <= std_logic_vector(divResult);
                                    debugLoad                                 <= '1';
                                end if;

                                if divStart = '0' and divComplete = '1' then
                                    TOS.word                                  <= unsigned(divResult(31 downto 0));
    
                                    mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incSp);
                                    mxFifo(to_integer(mxFifoWriteIdx)).cmd    <= MX_CMD_READNOS;
                                    NOS.valid                                 <= '0';
                                    mxFifoWriteIdx                            <= mxFifoWriteIdx + 1;
                                    state                                     <= State_Execute;
                                end if;
                            end if;

                        when State_Mod2 =>
                            if IMPL_MOD = true then
                                    if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                        debugRec.FMT_DATA_PRTMODE             <= "01";
                                        debugRec.FMT_PRE_SPACE                <= '0';
                                        debugRec.FMT_POST_SPACE               <= '1';
                                        debugRec.FMT_PRE_CR                   <= '1';
                                        debugRec.FMT_POST_CRLF                <= '1';
                                        debugRec.FMT_SPLIT_DATA               <= "00";
                                        debugRec.DATA_BYTECNT                 <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.DATA2_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA3_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA4_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.WRITE_DATA                   <= '1';
                                        debugRec.WRITE_DATA2                  <= '0';
                                        debugRec.WRITE_DATA3                  <= '0';
                                        debugRec.WRITE_DATA4                  <= '0';
                                        debugRec.WRITE_OPCODE                 <= '1';
                                        debugRec.WRITE_DECODED_OPCODE         <= '1';
                                        debugRec.WRITE_PC                     <= '1';
                                        debugRec.WRITE_SP                     <= '1';
                                        debugRec.WRITE_STACK_TOS              <= '1';
                                        debugRec.WRITE_STACK_NOS              <= '1';
                                        debugRec.DATA(63 downto 0)            <= "00" & std_logic_vector(divisorCopy(61 downto 0));
                                        debugRec.OPCODE                       <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                        debugRec.DECODED_OPCODE               <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                        debugRec.PC(ADDR_BIT_RANGE)           <= std_logic_vector(pc);
                                        debugRec.SP(ADDR_32BIT_RANGE)         <= std_logic_vector(sp);
                                        debugRec.STACK_TOS                    <= dividendCopy(31 downto 0);
                                        debugRec.STACK_NOS                    <= std_logic_vector(divRemainder);
                                        debugLoad                             <= '1';
                                    end if;

                                if divStart = '0' and divComplete = '1' then
                                    TOS.word                                  <= unsigned(divRemainder(31 downto 0));
    
                                    mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incSp);
                                    mxFifo(to_integer(mxFifoWriteIdx)).cmd    <= MX_CMD_READNOS;
                                    NOS.valid                                 <= '0';
                                    mxFifoWriteIdx                            <= mxFifoWriteIdx + 1;
                                    state                                     <= State_Execute;
                                end if;
                            end if;

                        when State_FiAdd2 =>
                            if IMPL_FIADD32 = true then
                                    if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                        debugRec.FMT_DATA_PRTMODE             <= "01";
                                        debugRec.FMT_PRE_SPACE                <= '0';
                                        debugRec.FMT_POST_SPACE               <= '1';
                                        debugRec.FMT_PRE_CR                   <= '1';
                                        debugRec.FMT_POST_CRLF                <= '1';
                                        debugRec.FMT_SPLIT_DATA               <= "00";
                                        debugRec.DATA_BYTECNT                 <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.DATA2_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA3_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA4_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.WRITE_DATA                   <= '1';
                                        debugRec.WRITE_DATA2                  <= '0';
                                        debugRec.WRITE_DATA3                  <= '0';
                                        debugRec.WRITE_DATA4                  <= '0';
                                        debugRec.WRITE_OPCODE                 <= '1';
                                        debugRec.WRITE_DECODED_OPCODE         <= '1';
                                        debugRec.WRITE_PC                     <= '1';
                                        debugRec.WRITE_SP                     <= '1';
                                        debugRec.WRITE_STACK_TOS              <= '1';
                                        debugRec.WRITE_STACK_NOS              <= '1';
                                        debugRec.DATA(63 downto 0)            <= "00" & std_logic_vector(divisorCopy(61 downto 0));
                                        debugRec.OPCODE                       <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                        debugRec.DECODED_OPCODE               <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                        debugRec.PC(ADDR_BIT_RANGE)           <= std_logic_vector(pc);
                                        debugRec.SP(ADDR_32BIT_RANGE)         <= std_logic_vector(sp);
                                        debugRec.STACK_TOS                    <= dividendCopy(31 downto 0);
                                        debugRec.STACK_NOS                    <= std_logic_vector(divResult);
                                        debugLoad                             <= '1';
                                    end if;
                                if divComplete = '1' and muxTOS.valid = '1' and muxNOS.valid = '1' then
                                    TOS.word                                  <= unsigned(fpAddResult(31 downto 0));
    
                                    mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incSp);
                                    mxFifo(to_integer(mxFifoWriteIdx)).cmd    <= MX_CMD_READNOS;
                                    NOS.valid                                 <= '0';
                                    mxFifoWriteIdx                            <= mxFifoWriteIdx + 1;
                                    state                                     <= State_Execute;
                                end if;
                            end if;

                        when State_FiDiv2 =>
                            if IMPL_FIDIV32 = true then
                                    if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                        debugRec.FMT_DATA_PRTMODE             <= "01";
                                        debugRec.FMT_PRE_SPACE                <= '0';
                                        debugRec.FMT_POST_SPACE               <= '1';
                                        debugRec.FMT_PRE_CR                   <= '1';
                                        debugRec.FMT_POST_CRLF                <= '1';
                                        debugRec.FMT_SPLIT_DATA               <= "00";
                                        debugRec.DATA_BYTECNT                 <= std_logic_vector(to_unsigned(7, 3));
                                        debugRec.DATA2_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA3_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.DATA4_BYTECNT                <= std_logic_vector(to_unsigned(0, 3));
                                        debugRec.WRITE_DATA                   <= '1';
                                        debugRec.WRITE_DATA2                  <= '0';
                                        debugRec.WRITE_DATA3                  <= '0';
                                        debugRec.WRITE_DATA4                  <= '0';
                                        debugRec.WRITE_OPCODE                 <= '1';
                                        debugRec.WRITE_DECODED_OPCODE         <= '1';
                                        debugRec.WRITE_PC                     <= '1';
                                        debugRec.WRITE_SP                     <= '1';
                                        debugRec.WRITE_STACK_TOS              <= '1';
                                        debugRec.WRITE_STACK_NOS              <= '1';
                                        debugRec.DATA(63 downto 0)            <= "00" & std_logic_vector(divisorCopy(61 downto 0));
                                        debugRec.OPCODE                       <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                        debugRec.DECODED_OPCODE               <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                        debugRec.PC(ADDR_BIT_RANGE)           <= std_logic_vector(pc);
                                        debugRec.SP(ADDR_32BIT_RANGE)         <= std_logic_vector(sp);
                                        debugRec.STACK_TOS                    <= dividendCopy(31 downto 0);
                                        debugRec.STACK_NOS                    <= std_logic_vector(divResult);
                                        debugLoad                             <= '1';
                                    end if;
                                if divComplete = '1' and muxTOS.valid = '1' and muxNOS.valid = '1' then
                                    TOS.word                                  <= unsigned(divResult(31 downto 0));
    
                                    mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incSp);
                                    mxFifo(to_integer(mxFifoWriteIdx)).cmd    <= MX_CMD_READNOS;
                                    NOS.valid                                 <= '0';
                                    mxFifoWriteIdx                            <= mxFifoWriteIdx + 1;
                                    state                                     <= State_Execute;
                                end if;
                            end if;

                        when State_FiMult2 =>
                            if IMPL_FIMULT32 = true then
                                if DEBUG_CPU = true and DEBUG_LEVEL >= 5 then
                                    debugRec.FMT_DATA_PRTMODE                 <= "01";
                                    debugRec.FMT_PRE_SPACE                    <= '0';
                                    debugRec.FMT_POST_SPACE                   <= '1';
                                    debugRec.FMT_PRE_CR                       <= '1';
                                    debugRec.FMT_POST_CRLF                    <= '1';
                                    debugRec.FMT_SPLIT_DATA                   <= "00";
                                    debugRec.DATA_BYTECNT                     <= std_logic_vector(to_unsigned(7, 3));
                                    debugRec.DATA2_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA3_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA4_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.WRITE_DATA                       <= '1';
                                    debugRec.WRITE_DATA2                      <= '0';
                                    debugRec.WRITE_DATA3                      <= '0';
                                    debugRec.WRITE_DATA4                      <= '0';
                                    debugRec.WRITE_OPCODE                     <= '1';
                                    debugRec.WRITE_DECODED_OPCODE             <= '1';
                                    debugRec.WRITE_PC                         <= '1';
                                    debugRec.WRITE_SP                         <= '1';
                                    debugRec.WRITE_STACK_TOS                  <= '1';
                                    debugRec.WRITE_STACK_NOS                  <= '1';
                                    debugRec.DATA(63 downto 0)                <= "00" & std_logic_vector(divisorCopy(61 downto 0));
                                    debugRec.OPCODE                           <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                    debugRec.DECODED_OPCODE                   <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                    debugRec.PC(ADDR_BIT_RANGE)               <= std_logic_vector(pc);
                                    debugRec.SP(ADDR_32BIT_RANGE)             <= std_logic_vector(sp);
                                    debugRec.STACK_TOS                        <= dividendCopy(31 downto 0);
                                    debugRec.STACK_NOS                        <= std_logic_vector(divResult);
                                    debugLoad                                 <= '1';
                                end if;

                                if divComplete = '1' and muxTOS.valid = '1' and muxNOS.valid = '1' then
                                    TOS.word                                  <= unsigned(fpMultResult(31 downto 0));
    
                                    mxFifo(to_integer(mxFifoWriteIdx)).addr(ADDR_32BIT_RANGE) <= std_logic_vector(incSp);
                                    mxFifo(to_integer(mxFifoWriteIdx)).cmd    <= MX_CMD_READNOS;
                                    NOS.valid                                 <= '0';
                                    mxFifoWriteIdx                            <= mxFifoWriteIdx + 1;
                                    state                                     <= State_Execute;
                                end if;
                            end if;

                        -- Should never reach this state, if debug enabled, output details.
                        when others =>    
                            sp                                                <= (others => DontCareValue);
                            report "Illegal state" severity failure;
                            inBreak                                           <= '1';

                            -- Debug code, if ENABLEd, writes out the current instruction.
                            if DEBUG_CPU = true and DEBUG_LEVEL >= 0 then
                                debugRec.FMT_DATA_PRTMODE                     <= "00";
                                debugRec.FMT_PRE_SPACE                        <= '0';
                                debugRec.FMT_POST_SPACE                       <= '0';
                                debugRec.FMT_PRE_CR                           <= '1';
                                debugRec.FMT_POST_CRLF                        <= '1';
                                debugRec.FMT_SPLIT_DATA                       <= "00";
                                debugRec.DATA_BYTECNT                         <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA2_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.DATA3_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.DATA4_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.WRITE_DATA                           <= '1';
                                debugRec.WRITE_DATA2                          <= '0';
                                debugRec.WRITE_DATA3                          <= '0';
                                debugRec.WRITE_DATA4                          <= '0';
                                debugRec.WRITE_OPCODE                         <= '1';
                                debugRec.WRITE_DECODED_OPCODE                 <= '1';
                                debugRec.WRITE_PC                             <= '1';
                                debugRec.WRITE_SP                             <= '1';
                                debugRec.WRITE_STACK_TOS                      <= '1';
                                debugRec.WRITE_STACK_NOS                      <= '1';
                                debugRec.DATA                                 <= X"494C4C4547414C53";
                                debugRec.OPCODE                               <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                debugRec.DECODED_OPCODE                       <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                debugRec.PC(ADDR_BIT_RANGE)                   <= std_logic_vector(pc);
                                debugRec.SP(ADDR_32BIT_RANGE)                 <= std_logic_vector(sp);
                                debugRec.STACK_TOS                            <= std_logic_vector(muxTOS.word);
                                debugRec.STACK_NOS                            <= std_logic_vector(muxNOS.word);
                                debugLoad                                     <= '1';
                            end if;
                    end case;
                    --------------------------------------------------------------------------------------------------------------
                    -- End of Instruction State Case block.
                    --------------------------------------------------------------------------------------------------------------

                else

                    -- In debug mode, output the current data and the decoded instruction queue.
                    if DEBUG_CPU = true then
                        case debugState is
                            when Debug_Idle =>

                            when Debug_Start =>

                                -- Write out the primary data.
                                debugRec.FMT_DATA_PRTMODE                     <= "01";
                                debugRec.FMT_PRE_SPACE                        <= '0';
                                debugRec.FMT_POST_SPACE                       <= '1';
                                debugRec.FMT_PRE_CR                           <= '1';
                                debugRec.FMT_POST_CRLF                        <= '1';
                                debugRec.FMT_SPLIT_DATA                       <= "11";
                                debugRec.DATA_BYTECNT                         <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA2_BYTECNT                        <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA3_BYTECNT                        <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA4_BYTECNT                        <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.WRITE_DATA                           <= '1';
                                debugRec.WRITE_DATA2                          <= '1';
                                debugRec.WRITE_DATA3                          <= '1';
                                debugRec.WRITE_DATA4                          <= '1';
                                debugRec.WRITE_OPCODE                         <= '1';
                                debugRec.WRITE_DECODED_OPCODE                 <= '1';
                                debugRec.WRITE_PC                             <= '1';
                                debugRec.WRITE_SP                             <= '1';
                                debugRec.WRITE_STACK_TOS                      <= '1';
                                debugRec.WRITE_STACK_NOS                      <= '1';
                                debugRec.DATA(63 downto 0)                    <= std_logic_vector(to_unsigned(to_integer(cacheL2FetchIdx), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1FetchIdx), 16))  & std_logic_vector(to_unsigned(to_integer(pc), 16)) & std_logic_vector(to_unsigned(to_integer(cacheL1StartAddr), 16));
                                debugRec.DATA2(63 downto 0)                   <= std_logic_vector(to_unsigned(to_integer(cacheL2FetchIdx), 16))  & std_logic_vector(to_unsigned(to_integer(cacheL2StartAddr), 16)) & std_logic_vector(cacheL2FetchIdx(15 downto 0))                   & "00" & cacheL1(to_integer(pc))(DECODED_RANGE) & "0000" & idimFlag & tInsnExec & cacheL2Full & cacheL2Write;
                                debugRec.DATA3(63 downto 0)                   <= "00" & cacheL1(to_integer(pc))(DECODED_RANGE) & cacheL1(to_integer(pc))(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+1)(DECODED_RANGE) & cacheL1(to_integer(pc)+1)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+2)(DECODED_RANGE) & cacheL1(to_integer(pc)+2)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+3)(DECODED_RANGE) & cacheL1(to_integer(pc)+3)(OPCODE_RANGE);
                                debugRec.DATA4(63 downto 0)                   <= "00" & cacheL1(to_integer(pc)+4)(DECODED_RANGE) & cacheL1(to_integer(pc)+4)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+5)(DECODED_RANGE) & cacheL1(to_integer(pc)+5)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+6)(DECODED_RANGE) & cacheL1(to_integer(pc)+6)(OPCODE_RANGE) & "00" & cacheL1(to_integer(pc)+7)(DECODED_RANGE) & cacheL1(to_integer(pc)+7)(OPCODE_RANGE);
                                debugRec.OPCODE                               <= cacheL1(to_integer(pc))(OPCODE_RANGE);
                                debugRec.DECODED_OPCODE                       <= cacheL1(to_integer(pc))(DECODED_RANGE);
                                debugRec.PC(ADDR_BIT_RANGE)                   <= std_logic_vector(pc);
                                debugRec.SP(ADDR_32BIT_RANGE)                 <= std_logic_vector(sp);
                                debugRec.STACK_TOS                            <= std_logic_vector(muxTOS.word);
                                debugRec.STACK_NOS                            <= std_logic_vector(muxNOS.word);
                                debugLoad                                     <= '1';
                                debugAllInfo                                  <= '1';

                                debugState                                    <= Debug_DumpL1;

                            when Debug_DumpL1 =>
                                debugPC                                       <= (others => '0');
                                debugState                                    <= Debug_DumpL1_1;

                            when Debug_DumpL1_1 =>
                                -- Write out the opcode.
                                debugRec.FMT_DATA_PRTMODE                     <= "01";
                                debugRec.FMT_PRE_SPACE                        <= '0';
                                debugRec.FMT_POST_SPACE                       <= '0';
                                debugRec.FMT_PRE_CR                           <= '1';
                                debugRec.FMT_SPLIT_DATA                       <= "01";
                                if debugPC = MAX_L1CACHE_SIZE-(wordBytes*4) then
                                    debugRec.FMT_POST_CRLF                    <= '1';
                                else
                                    debugRec.FMT_POST_CRLF                    <= '0';
                                end if;
                                debugRec.DATA_BYTECNT                         <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA2_BYTECNT                        <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA3_BYTECNT                        <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA4_BYTECNT                        <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.WRITE_DATA                           <= '1';
                                debugRec.WRITE_DATA2                          <= '1';
                                debugRec.WRITE_DATA3                          <= '1';
                                debugRec.WRITE_DATA4                          <= '1';
                                debugRec.WRITE_OPCODE                         <= '0';
                                debugRec.WRITE_DECODED_OPCODE                 <= '0';
                                debugRec.WRITE_PC                             <= '0';
                                debugRec.WRITE_SP                             <= '0';
                                debugRec.WRITE_STACK_TOS                      <= '0';
                                debugRec.WRITE_STACK_NOS                      <= '0';
                                debugRec.OPCODE                               <= (others => '0');
                                debugRec.DECODED_OPCODE                       <= (others => '0');
                                debugRec.DATA(63 downto 0)                    <= "00" & cacheL1(to_integer(debugPC)+ 0)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 1)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 2)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 3)(INSN_RANGE);
                                debugRec.DATA2(63 downto 0)                   <= "00" & cacheL1(to_integer(debugPC)+ 4)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 5)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 6)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 7)(INSN_RANGE);
                                debugRec.DATA3(63 downto 0)                   <= "00" & cacheL1(to_integer(debugPC)+ 8)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+ 9)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+10)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+11)(INSN_RANGE);
                                debugRec.DATA4(63 downto 0)                   <= "00" & cacheL1(to_integer(debugPC)+12)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+13)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+14)(INSN_RANGE) & "00" & cacheL1(to_integer(debugPC)+15)(INSN_RANGE);
                                if debugPC = 0 then
                                    debugRec.PC(ADDR_BIT_RANGE)               <= std_logic_vector(to_unsigned(to_integer(pc), debugRec.PC'LENGTH));
                                    debugRec.WRITE_PC                         <= '1';
                                else
                                    debugRec.WRITE_PC                         <= '0';
                                end if;
                                debugLoad                                     <= '1';
                                debugState                                    <= Debug_DumpL1_2;
                                debugPC                                       <= debugPC + (wordBytes * 4);  -- 16 instructions are output per loop.

                            when Debug_DumpL1_2 =>
                                -- Move onto next opcode in Fifo.
                                if debugPC = MAX_L1CACHE_SIZE then
                                    if debugAllInfo = '1' then
                                    --    if IMPL_USE_INSN_BUS = true then
                                    --        debugState                        <= Debug_End;
                                    --    else
                                            debugState                        <= Debug_DumpL2;
                                    --    end if;
                                    else
                                        debugState                            <= Debug_End;
                                    end if;
                                else
                                    debugState                                <= Debug_DumpL1_1;
                                end if;

                            when Debug_DumpL2 =>
                                debugPC                                       <= (others => '0');
                                debugState                                    <= Debug_DumpL2_0;

                            -- Wait state at start of dump so initial address gets registered in cache memory and data output.
                            when Debug_DumpL2_0 =>
                                debugState                                    <= Debug_DumpL2_1;

                            -- Output the contents of L2 in the format <addr> <instruction ... x 20>
                            when Debug_DumpL2_1 =>
                                -- Write out the opcode.
                                debugRec.FMT_DATA_PRTMODE                     <= "01";
                                debugRec.FMT_PRE_SPACE                        <= '0';
                                debugRec.FMT_POST_SPACE                       <= '0';
                                debugRec.FMT_PRE_CR                           <= '1';
                                debugRec.FMT_SPLIT_DATA                       <= "01";
                                if debugPC = MAX_L2CACHE_SIZE-1 or debugPC(4 downto 3) = "11" then
                                    debugRec.FMT_POST_CRLF                    <= '1';
                                else
                                    debugRec.FMT_POST_CRLF                    <= '0';
                                end if;
                                debugRec.DATA_BYTECNT                         <= std_logic_vector(to_unsigned(7, 3));
                                debugRec.DATA2_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.DATA3_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.DATA4_BYTECNT                        <= std_logic_vector(to_unsigned(0, 3));
                                debugRec.WRITE_DATA                           <= '1';
                                debugRec.WRITE_DATA2                          <= '0';
                                debugRec.WRITE_DATA3                          <= '0';
                                debugRec.WRITE_DATA4                          <= '0';
                                debugRec.WRITE_OPCODE                         <= '0';
                                debugRec.WRITE_DECODED_OPCODE                 <= '0';
                                if debugPC(4 downto 3) = "0000" then
                                    debugRec.WRITE_PC                         <= '1';
                                else
                                    debugRec.WRITE_PC                         <= '0';
                                end if;
                                debugRec.WRITE_SP                             <= '0';
                                debugRec.WRITE_STACK_TOS                      <= '0';
                                debugRec.WRITE_STACK_NOS                      <= '0';
                                debugRec.OPCODE                               <= (others => '0'); 
                                debugRec.DECODED_OPCODE                       <= (others => '0');
                                debugRec.PC(ADDR_BIT_RANGE)                   <= std_logic_vector(debugPC);
                                debugRec.DATA                                 <= cacheL2Word;
                                debugLoad                                     <= '1';
                                debugState                                    <= Debug_DumpL2_2;
                                debugPC                                       <= debugPC + longWordBytes; -- 8 instructions are output per loop (limited by memory read into cacheL2Word).

                            when Debug_DumpL2_2 =>
                                -- Move onto next opcode in Fifo.
                                if debugPC = MAX_L2CACHE_SIZE then
                                    if debugAllInfo = '1' then
                                        debugState                            <= Debug_DumpMem;
                                    else
                                        debugState                            <= Debug_End;
                                    end if;
                                else
                                    debugState                                <= Debug_DumpL2_1;
                                end if;

                            when Debug_DumpMem =>
                                debugPC                                       <= debugPC_StartAddr;
                                debugPC_WidthCounter                          <= 0;
                                debugState                                    <= Debug_DumpMem_0;

                            when Debug_DumpMem_0 =>
                                if mxMemVal.valid = '1' then
                                    debugState                                <= Debug_DumpMem_1;
                                end if;

                            -- Output the contents of memory in the format <addr> <word ... x 20>
                            when Debug_DumpMem_1 =>
                                if mxMemVal.valid = '1' then
                                    debugPC_WidthCounter                      <= debugPC_WidthCounter+4;

                                    -- Write out the memory location.
                                    debugRec.FMT_DATA_PRTMODE                 <= "01";
                                    debugRec.FMT_PRE_SPACE                    <= '0';
                                    debugRec.FMT_POST_SPACE                   <= '0';
                                    debugRec.FMT_PRE_CR                       <= '1';
                                    debugRec.FMT_SPLIT_DATA                   <= "01";
                                    if debugPC = debugPC_EndAddr or debugPC_WidthCounter = debugPC_Width-4 then
                                        debugRec.FMT_POST_CRLF                <= '1';
                                        debugPC_WidthCounter                  <= 0;
                                    else
                                        debugRec.FMT_POST_CRLF                <= '0';
                                    end if;
                                    debugRec.DATA_BYTECNT                     <= std_logic_vector(to_unsigned(3, 3));
                                    debugRec.DATA2_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA3_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA4_BYTECNT                    <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.WRITE_DATA                       <= '1';
                                    debugRec.WRITE_DATA2                      <= '0';
                                    debugRec.WRITE_DATA3                      <= '0';
                                    debugRec.WRITE_DATA4                      <= '0';
                                    debugRec.WRITE_OPCODE                     <= '0';
                                    debugRec.WRITE_DECODED_OPCODE             <= '0';
                                    if debugPC_WidthCounter = 0 then
                                        debugRec.WRITE_PC                     <= '1';
                                    else
                                        debugRec.WRITE_PC                     <= '0';
                                    end if;
                                    debugRec.WRITE_SP                         <= '0';
                                    debugRec.WRITE_STACK_TOS                  <= '0';
                                    debugRec.WRITE_STACK_NOS                  <= '0';
                                    debugRec.OPCODE                           <= (others => '0'); 
                                    debugRec.DECODED_OPCODE                   <= (others => '0');
                                    debugRec.PC(ADDR_BIT_RANGE)               <= std_logic_vector(debugPC);
                                    debugRec.DATA(63 downto 32)               <= std_logic_vector(mxMemVal.word(31 downto 24)) & std_logic_vector(mxMemVal.word(23 downto 16)) & std_logic_vector(mxMemVal.word(15 downto 8)) & std_logic_vector(mxMemVal.word(7 downto 0));
                                    debugLoad                                 <= '1';
                                    debugState                                <= Debug_DumpMem_2;
                                    debugPC                                   <= debugPC + wordBytes;
                                end if;

                            when Debug_DumpMem_2 =>
                                -- Move onto next opcode in Fifo.
                                if debugPC = debugPC_EndAddr then
                                    debugState                                <= Debug_End;
                                else
                                    debugState                                <= Debug_DumpMem_1;
                                end if;

                            when Debug_End =>
                                debugAllInfo                                  <= '0';
                                debugState                                    <= Debug_Idle;
                        end case;
                    end if; 
                end if;
            end if;
            ---------------------------------------------------------------------------------------------------------------------------------------------------
        end if;
    end process;

    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Hardware divider - Fixed Point.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    DIVIDER : if IMPL_DIV = true or IMPL_FIDIV32 = true or IMPL_MOD = true generate
        process(CLK, ZPURESET, divStart, dividendCopy)
        begin
            divRemainder                                 <= unsigned(dividendCopy(31 downto 0));
    
            if ZPURESET = '1' then
                divComplete                              <= '1';
                divResult                                <= (others => '0');
    
            elsif rising_edge(CLK) then
    
                if divComplete = '1' and divStart = '1' then
                    divComplete                          <= '0';
                    bitCnt                               <= to_unsigned((32+divQuotientFractional)-2, bitCnt'LENGTH);
                    divResult                            <= (others => '0');
    
                    dividendCopy(30 downto 0)            <= std_logic_vector(muxTOS.word(30 downto 0));
                    dividendCopy(61 downto 31)           <= (others => '0');
    
                    divisorCopy(61)                      <= '0';
                    divisorCopy(60 downto 30)            <= std_logic_vector(muxNOS.word(30 downto 0));
                    divisorCopy(29 downto 0)             <= (others => '0');
    
                    -- set sign bit
                    if((muxTOS.word(31) = '1' and muxNOS.word(31) = '0') or (muxTOS.word(31) = '0' and muxNOS.word(31) = '1')) then
                        divResult(31)                    <= '1';
                    else
                        divResult(31)                    <= '0';
                    end if;
    
                elsif divComplete = '0' and (DEBUG_CPU = false or (DEBUG_CPU = true and debugReady = '1')) then
                    -- 64bit compare of divisor/dividend.
                    if((unsigned(dividendCopy)) >= unsigned(divisorCopy)) then
                        --subtract, should only occur when the dividend is greater than the divisor.
                        dividendCopy                     <= std_logic_vector(to_unsigned(to_integer(unsigned(dividendCopy)) - to_integer(unsigned(divisorCopy)), dividendCopy'LENGTH));
                        --set quotient
                        divResult(to_integer(bitCnt))    <= '1';
                    end if;
         
                    --reduce divisor
                    divisorCopy                          <= to_stdlogicvector(to_bitvector(divisorCopy) srl 1);
          
                    --stop condition
                    if bitCnt = 0 then
                        divComplete                      <= '1';
                    else
                        --reduce bit counter
                        bitCnt                           <= bitCnt - 1;
                    end if;
                end if;
            end if;
        end process;        
    else generate
        dividendCopy                                     <= (others => DontCareValue);
    end generate;
    
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Hardware adder - Fixed Point.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    FIADD32: if IMPL_FIADD32 = true generate
        process(muxTOS.word, muxNOS.word, ZPURESET)
        begin
            if ZPURESET = '1' then
                fpAddResult                              <= (others => '0');
            else
                -- both negative
                if muxTOS.word(31) = '1' and muxNOS.word(31) = '1' then
                    -- sign
                    fpAddResult(31)                      <= '1';
                    -- whole
                    fpAddResult(30 downto 0)             <= std_logic_vector(to_unsigned(to_integer(muxTOS.word(30 downto 0)) + to_integer(muxNOS.word(30 downto 0)), 31));
        
                --both positive
                elsif muxTOS.word(31) = '0' and muxNOS.word(31) = '0' then
                    -- sign
                    fpAddResult(31)                      <= '0';
                    -- whole
                    fpAddResult(30 downto 0)             <= std_logic_vector(to_unsigned(to_integer(muxTOS.word(30 downto 0)) + to_integer(muxNOS.word(30 downto 0)), 31));
        
                -- subtract TOS - NOS
                elsif muxTOS.word(31) = '0' and muxNOS.word(31) = '1' then
                    -- sign
                    if muxTOS.word(30 downto 0) > muxNOS.word(30 downto 0) then
                        fpAddResult(31)                  <= '1';
                    else
                        fpAddResult(31)                  <= '0';
                    end if;
                    -- whole
                    fpAddResult(30 downto 0)             <= std_logic_vector(to_unsigned(to_integer(muxTOS.word(30 downto 0)) - to_integer(muxNOS.word(30 downto 0)), 31));
        
                -- subtract NOS - TOS
                else 
                    -- sign
                    if muxTOS.word(30 downto 0) < muxNOS.word(30 downto 0) then
                        fpAddResult(31)                  <= '1';
                    else
                        fpAddResult(31)                  <= '0';
                    end if;
                    -- whole
                    fpAddResult(30 downto 0)             <= std_logic_vector(to_unsigned(to_integer(muxNOS.word(30 downto 0)) - to_integer(muxTOS.word(30 downto 0)), 31));
                end if;
            end if;
        end process;
    else generate
        fpAddResult                                      <= (others => DontCareValue);
    end generate;
    
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Hardware multiplier - Fixed Point.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    FIMULT32: if IMPL_FIMULT32 = true generate
        signal TOSflip                                   : std_logic_vector(31 downto 0);
        signal NOSflip                                   : std_logic_vector(31 downto 0);
        signal TOSmult                                   : std_logic_vector(31 downto 0);
        signal NOSmult                                   : std_logic_vector(31 downto 0);
        signal resultFlip                                : std_logic_vector(63 downto 0);
        signal result                                    : std_logic_vector(63 downto 0);
    begin
        process(muxTOS.word, TOSflip)
        begin
            for i in 0 to wordSize-1 loop
               TOSflip(i)                                <= muxTOS.word(wordSize-1-i);
            end loop;
            TOSflip                                      <= std_logic_vector(signed(TOSflip) + 1);
        end process;
    
        process(muxNOS.word, NOSflip)
        begin
            for i in 0 to wordSize-1 loop
               NOSflip(i)                                <= muxNOS.word(wordSize-1-i);
            end loop;
            NOSflip                                      <= std_logic_vector(signed(NOSflip) + 1);
        end process;
    
        process(result, quotientFractional, resultFlip)
        begin
            for i in quotientFractional to 30+quotientFractional loop
               resultFlip(i)                             <= result(30+quotientFractional-i);
            end loop;
            resultFlip                                   <= std_logic_vector(signed(resultFlip) + 1);
        end process;
    
        process(muxTOS.word, muxNOS.word, TOSflip, NOSflip)
        begin
            if muxTOS.word(31) = '1' then
                TOSmult                                  <= TOSflip;
            else
                TOSmult                                  <= std_logic_vector(muxTOS.word);
            end if;
    
            if muxNOS.word(31) = '1' then
                NOSmult                                  <= NOSflip;
            else
                NOSmult                                  <= std_logic_vector(muxNOS.word);
            end if;
        end process;
    
        process(TOSmult, NOSmult)
        begin
            result                                       <= std_logic_vector(signed(TOSmult) * signed(NOSmult));
        end process;
    
        process(result, resultFlip, muxTOS.word, muxNOS.word, quotientFractional)
        begin
            -- sign
            if (muxTOS.word(31) = '1' and muxNOS.word(31) = '0') or (muxTOS.word(31) = '0' and muxNOS.word(31) = '1') then
                fpMultResult(31)                         <= '1';
                fpMultResult(30 downto 0)                <= resultFlip(30 downto 0);
            else
                fpMultResult(31)                         <= '0';
                fpMultResult(30 downto 0)                <= result(30+quotientFractional downto quotientFractional);
            end if;
        end process;
    else generate
        fpMultResult                                     <= (others => DontCareValue);
        quotientFractional                               <= 0;
    end generate;

    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Debugger output processor.
    -- This logic takes a debug record and expands it to human readable form then dispatches it to the debug serial port.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- Add debug uart if required. Increasing the TX and DBG Fifo depth can help short term (ie. initial start of the CPU)
    -- but once full, the debug run will eventually operate at the slowest denominator, ie. the TX speed and how quick it can
    -- shift 10 bits.
    DEBUG : if DEBUG_CPU = true generate
        DEBUGUART: entity work.zpu_uart_debug
            generic map (
                CLK_FREQ                 => CLK_FREQ                         -- Frequency of master clock.
            )
            port map (
                -- CPU Interface
                CLK                      => CLK,                             -- Master clock
                RESET                    => ZPURESET,                        -- high active sync reset
                DEBUG_DATA               => debugRec,                        -- write data
                CS                       => debugLoad,                       -- Chip Select.
                READY                    => debugReady,                      -- Debug processor ready for next command.
    
                -- Serial data
                TXD                      => DEBUG_TXD
            );
    end generate;
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- End of debugger output processor.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------

end behave;
