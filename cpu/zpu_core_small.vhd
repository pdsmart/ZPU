-- ZPU
--
-- Copyright 2004-2008 oharboe - Øyvind Harboe - oyvind.harboe@zylin.com
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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library work;
use work.zpu_pkg.all;

entity zpu_core_small is
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
        out_mem_bEnable           : out std_logic;  -- Enable byte write
        out_mem_hEnable           : out std_logic;  -- Enable halfword write
        out_mem_readEnable        : out std_logic;
        -- this implementation of the ZPU *always* reads and writes entire
        -- 32 bit words, so mem_writeMask is tied to (others => '1').
        mem_writeMask             : out std_logic_vector(WORD_4BYTE_RANGE);
        -- Set to one to jump to interrupt vector
        -- The ZPU will communicate with the hardware that caused the
        -- interrupt via memory mapped IO or the interrupt flag can
        -- be cleared automatically
        interrupt_request         : in  std_logic;
        interrupt_ack             : out std_logic; -- Interrupt acknowledge, ZPU has entered Interrupt Service Routine.
        interrupt_done            : out std_logic; -- Interrupt service routine completed/done.
        -- Signal that the break instruction is executed, normally only used
        -- in simulation to stop simulation
        break                     : out std_logic;
        debug_txd                 : out std_logic; -- Debug serial output.
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
end zpu_core_small;

architecture behave of zpu_core_small is

    -- state machine.
    type State_Type is
    (
        State_Fetch,
        State_WriteIODone,
        State_Execute,
        State_StoreToStack,
        State_Add,
        State_Or,
        State_And,
        State_Store,
        State_ReadIO,
        State_WriteIO,
        State_Load,
        State_FetchNext,
        State_AddSP,
        State_ReadIODone,
        State_Decode,
        State_Resync,
        State_Interrupt,
        State_Debug
    );
    
    type DecodedOpcodeType is
    (
        Decoded_Nop,
        Decoded_Im,
        Decoded_ImShift,
        Decoded_LoadSP,
        Decoded_StoreSP    ,
        Decoded_AddSP,
        Decoded_Emulate,
        Decoded_Break,
        Decoded_PushSP,
        Decoded_PopPC,
        Decoded_Add,
        Decoded_Or,
        Decoded_And,
        Decoded_Load,
        Decoded_Not,
        Decoded_Flip,
        Decoded_Store,
        Decoded_PopSP,
        Decoded_Interrupt
    );

    --
    type DebugType is 
    (
        Debug_Start,
        Debug_DumpFifo,
        Debug_DumpFifo_1,
        Debug_End
    );
    
    signal readIO                          : std_logic;
    
    signal memAWriteEnable                 : std_logic;
    signal memAAddr                        : unsigned(ADDR_32BIT_RANGE);
    signal memAWrite                       : unsigned(WORD_32BIT_RANGE);
    signal memARead                        : unsigned(WORD_32BIT_RANGE);
    signal memBWriteEnable                 : std_logic;
    signal memBAddr                        : unsigned(ADDR_32BIT_RANGE);
    signal memBWrite                       : unsigned(WORD_32BIT_RANGE);
    signal memBRead                        : unsigned(WORD_32BIT_RANGE);
     
    signal pc                              : unsigned(ADDR_BIT_RANGE);
    signal sp                              : unsigned(ADDR_32BIT_RANGE);
    signal interrupt_suspended_addr        : unsigned(ADDR_BIT_RANGE);
    
    -- this signal is set upon executing an IM instruction
    -- the subsequence IM instruction will then behave differently.
    -- all other instructions will clear the idim_flag.
    -- this yields highly compact immediate instructions.
    signal idim_flag                       : std_logic;
    
    signal busy                            : std_logic;
    
    signal begin_inst                      : std_logic;
    
    signal trace_opcode                    : std_logic_vector(7 downto 0);
    signal trace_pc                        : std_logic_vector(ADDR_BIT_RANGE);
    signal trace_sp                        : std_logic_vector(ADDR_32BIT_RANGE);
    signal trace_topOfStack                : std_logic_vector(WORD_32BIT_RANGE);
    signal trace_topOfStackB               : std_logic_vector(WORD_32BIT_RANGE);
    signal debugState                      : DebugType;
    signal debugCnt                        : integer;
    signal debugRec                        : zpu_dbg_t;
    signal debugLoad                       : std_logic;
    signal debugReady                      : std_logic;
    
    signal sampledOpcode                   : std_logic_vector(OpCode_Size-1 downto 0);
    signal opcode                          : std_logic_vector(OpCode_Size-1 downto 0);
    
    signal decodedOpcode                   : DecodedOpcodeType;
    signal sampledDecodedOpcode            : DecodedOpcodeType;
    
    signal state                           : State_Type;
    
    subtype index is integer range 0 to 3;
    
    signal tOpcode_sel                     : index;
    
    signal inInterrupt                     : std_logic;

begin

    -- generate a trace file.
    -- 
    -- This is only used in simulation to see what instructions are
    -- executed. 
    --
    -- a quick & dirty regression test is then to commit trace files
    -- to CVS and compare the latest trace file against the last known
    -- good trace file
--    traceFileGenerate:
--    if Generate_Trace generate
--    trace_file: trace port map (
--           clk => clk,
--           begin_inst => begin_inst,
--           pc => trace_pc,
--        opcode => trace_opcode,
--        sp => trace_sp,
--        memA => trace_topOfStack,
--        memB => trace_topOfStackB,
--        busy => busy,
--        intsp => (others => 'U')
--        );
--    end generate;


    -- Not yet implemented.
    out_mem_bEnable                        <= '0';  -- Enable byte write
    out_mem_hEnable                        <= '0';  -- Enable halfword write

    -- Wire up the RAM/ROM
    MEM_A_ADDR                             <= std_logic_vector(memAAddr(ADDR_32BIT_RANGE));
    MEM_A_WRITE                            <= std_logic_vector(memAWrite);
    MEM_B_ADDR                             <= std_logic_vector(memBAddr(ADDR_32BIT_RANGE));
    MEM_B_WRITE                            <= std_logic_vector(memBWrite);
    memARead                               <= unsigned(MEM_A_READ);
    memBRead                               <= unsigned(MEM_B_READ);
    MEM_A_WRITE_ENABLE                     <= memAWriteEnable;
    MEM_B_WRITE_ENABLE                     <= memBWriteEnable;
         
    -- mem_writeMask is not used in this design, tie it to 1
    mem_writeMask                          <= (others => '1');
    
    tOpcode_sel                            <= to_integer(pc(minAddrBit-1 downto 0));

    -- move out calculation of the opcode to a seperate process
    -- to make things a bit easier to read
    decodeControl: process(memBRead, pc,tOpcode_sel)
        variable tOpcode          : std_logic_vector(OpCode_Size-1 downto 0);
    begin

        -- simplify opcode selection a bit so it passes more synthesizers
        case (tOpcode_sel) is

            when 0 => tOpcode              := std_logic_vector(memBRead(31 downto 24));

            when 1 => tOpcode              := std_logic_vector(memBRead(23 downto 16));

            when 2 => tOpcode              := std_logic_vector(memBRead(15 downto 8));

            when 3 => tOpcode              := std_logic_vector(memBRead(7 downto 0));

            when others => tOpcode         := std_logic_vector(memBRead(7 downto 0));
        end case;

        sampledOpcode                      <= tOpcode;

        if (tOpcode(7 downto 7) = OpCode_Im) then
            sampledDecodedOpcode           <= Decoded_Im;
        elsif (tOpcode(7 downto 5)=OpCode_StoreSP) then
            sampledDecodedOpcode           <= Decoded_StoreSP;
        elsif (tOpcode(7 downto 5)=OpCode_LoadSP) then
            sampledDecodedOpcode           <= Decoded_LoadSP;
        elsif (tOpcode(7 downto 5)=OpCode_Emulate) then
            sampledDecodedOpcode           <= Decoded_Emulate;
        elsif (tOpcode(7 downto 4)=OpCode_AddSP) then
            sampledDecodedOpcode           <= Decoded_AddSP;
        else
            case tOpcode(3 downto 0) is
                when OpCode_Break =>
                    sampledDecodedOpcode   <= Decoded_Break;
                when OpCode_PushSP =>
                    sampledDecodedOpcode   <= Decoded_PushSP;
                when OpCode_PopPC =>
                    sampledDecodedOpcode   <= Decoded_PopPC;
                when OpCode_Add =>
                    sampledDecodedOpcode   <= Decoded_Add;
                when OpCode_Or =>
                    sampledDecodedOpcode   <= Decoded_Or;
                when OpCode_And =>
                    sampledDecodedOpcode   <= Decoded_And;
                when OpCode_Load =>
                    sampledDecodedOpcode   <= Decoded_Load;
                when OpCode_Not =>
                    sampledDecodedOpcode   <= Decoded_Not;
                when OpCode_Flip =>
                    sampledDecodedOpcode   <= Decoded_Flip;
                when OpCode_Store =>
                    sampledDecodedOpcode   <= Decoded_Store;
                when OpCode_PopSP =>
                    sampledDecodedOpcode   <= Decoded_PopSP;
                when others =>
                    sampledDecodedOpcode   <= Decoded_Nop;
            end case;
        end if;
    end process;


    opcodeControl:
    process(clk, areset)
        variable spOffset : unsigned(4 downto 0);
    begin
        if areset = '1' then
            state                              <= State_Resync;
            break                              <= '0';
            sp                                 <= to_unsigned(STACK_ADDR, maxAddrBit)(ADDR_32BIT_RANGE);
            pc                                 <= (others => '0');
            idim_flag                          <= '0';
            begin_inst                         <= '0';
            memAAddr                           <= (others => '0');
            memBAddr                           <= (others => '0');
            memAWriteEnable                    <= '0';
            memBWriteEnable                    <= '0';
            out_mem_writeEnable                <= '0';
            out_mem_readEnable                 <= '0';
            memAWrite                          <= (others => '0');
            memBWrite                          <= (others => '0');
            inInterrupt                        <= '0';
            interrupt_ack                      <= '0';
            interrupt_done                     <= '0';
            if DEBUG_CPU = true then
                debugRec                       <= ZPU_DBG_T_INIT;
                debugCnt                       <= 0;
                debugLoad                      <= '0';
            end if;

        elsif (clk'event and clk = '1') then

            if DEBUG_CPU = true then
                debugLoad                      <= '0';
            end if;            

            memAWriteEnable                    <= '0';
            memBWriteEnable                    <= '0';

            -- If the cpu can run, continue with next state.
            --
            if DEBUG_CPU = false or (DEBUG_CPU = true and debugReady = '1') then    

                -- This saves ca. 100 LUT's, by explicitly declaring that the
                -- memAWrite can be left at whatever value if memAWriteEnable is
                -- not set.
                memAWrite                      <= (others => DontCareValue);
                memBWrite                      <= (others => DontCareValue);
    --          out_mem_addr                   <= (others => DontCareValue);
    --          mem_write                      <= (others => DontCareValue);
                spOffset                       := (others => DontCareValue);
                memAAddr                       <= (others => DontCareValue);
                memBAddr                       <= (others => DontCareValue);

                out_mem_writeEnable            <= '0';
                out_mem_readEnable             <= '0';
                begin_inst                     <= '0';
                out_mem_addr                   <= std_logic_vector(memARead(ADDR_BIT_RANGE));
                mem_write                      <= std_logic_vector(memBRead);
            
                decodedOpcode                  <= sampledDecodedOpcode;
                opcode                         <= sampledOpcode;
    
                -- If interrupt is active, we only clear the interrupt state once the PC is reset to the address which was suspended after the
                -- interrupt, this prevents recursive interrupt triggers, desirable in cetain circumstances but not for this current design.
                --
                interrupt_ack                  <= '0';             -- Reset interrupt acknowledge if set, width is 1 clock only.
                interrupt_done                 <= '0';             -- Reset interrupt done if set, width is 1 clock only.
                if inInterrupt = '1' and pc(ADDR_BIT_RANGE) = interrupt_suspended_addr(ADDR_BIT_RANGE) then
                    inInterrupt                <= '0';             -- no longer in an interrupt
                    interrupt_done             <= '1';             -- Interrupt service routine complete.
                end if;

                case state is
                    when State_Execute =>
                        state                                       <= State_Fetch;
                        -- at this point:
                        -- memBRead contains opcode word
                        -- memARead contains top of stack
                        pc                                          <= pc + 1;
        
                        -- trace
                      --begin_inst                        <= '1';
                      --trace_pc                          <= (others => '0');
                      --trace_pc(ADDR_BIT_RANGE)          <= std_logic_vector(pc);
                      --trace_opcode                      <= opcode;
                      --trace_sp                          <= (others => '0');
                      --trace_sp(ADDR_32BIT_RANGE)        <= std_logic_vector(sp);
                      --trace_topOfStack                  <= std_logic_vector(memARead);
                      --trace_topOfStackB                 <= std_logic_vector(memBRead);

                        -- during the next cycle we'll be reading the next opcode    
                        spOffset(4)                                 :=not opcode(4);
                        spOffset(3 downto 0)                        := unsigned(opcode(3 downto 0));
        
                        -- Debug code, if enabled, writes out the current instruction.
                        if DEBUG_CPU = true and DEBUG_LEVEL >= 1 then
                            debugRec.FMT_DATA_PRTMODE               <= "00";
                            debugRec.FMT_PRE_SPACE                  <= '0';
                            debugRec.FMT_POST_SPACE                 <= '0';
                            debugRec.FMT_PRE_CR                     <= '1';
                            debugRec.FMT_POST_CRLF                  <= '1';
                            debugRec.FMT_SPLIT_DATA                 <= "00";
                            debugRec.DATA_BYTECNT                   <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.DATA2_BYTECNT                  <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.DATA3_BYTECNT                  <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.DATA4_BYTECNT                  <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.WRITE_DATA                     <= '0';
                            debugRec.WRITE_DATA2                    <= '0';
                            debugRec.WRITE_DATA3                    <= '0';
                            debugRec.WRITE_DATA4                    <= '0';
                            debugRec.WRITE_OPCODE                   <= '1';
                            debugRec.WRITE_DECODED_OPCODE           <= '1';
                            debugRec.WRITE_PC                       <= '1';
                            debugRec.WRITE_SP                       <= '1';
                            debugRec.WRITE_STACK_TOS                <= '1';
                            debugRec.WRITE_STACK_NOS                <= '1';
                            debugRec.DATA(63 downto 0)              <= (others => '0');
                            debugRec.DATA2(63 downto 0)             <= (others => '0');
                            debugRec.DATA3(63 downto 0)             <= (others => '0');
                            debugRec.DATA4(63 downto 0)             <= (others => '0');
                            debugRec.OPCODE                         <= opcode;
                            debugRec.DECODED_OPCODE                 <= std_logic_vector(to_unsigned(DecodedOpcodeType'POS(decodedOpcode), 6));
                            debugRec.PC(ADDR_BIT_RANGE)             <= std_logic_vector(pc);
                            debugRec.SP(ADDR_32BIT_RANGE)           <= std_logic_vector(sp);
                            debugRec.STACK_TOS                      <= std_logic_vector(memARead);
                            debugRec.STACK_NOS                      <= std_logic_vector(memBRead);
                            debugLoad                               <= '1';
                        end if;
    
                        idim_flag                                   <= '0';
                        case decodedOpcode is
                            when Decoded_Interrupt =>
                                interrupt_ack                       <= '1';                           -- Acknowledge interrupt.
                                interrupt_suspended_addr            <= pc(ADDR_BIT_RANGE);            -- Save address which got interrupted.
                                sp                                  <= sp - 1;
                                memAAddr                            <= sp - 1;
                                memAWriteEnable                     <= '1';
                                memAWrite                           <= (others => DontCareValue);
                                memAWrite(ADDR_BIT_RANGE)           <= pc;
                                pc                                  <= to_unsigned(32, maxAddrBit); -- interrupt address
                                report "ZPU jumped to interrupt!" severity note;
                            when Decoded_Im =>
                                idim_flag                           <= '1';
                                memAWriteEnable                     <= '1';
                                if (idim_flag='0') then
                                    sp                              <= sp - 1;
                                    memAAddr                        <= sp-1;
                                    for i in wordSize-1 downto 7 loop
                                        memAWrite(i)                <= opcode(6);
                                    end loop;
                                    memAWrite(6 downto 0)           <= unsigned(opcode(6 downto 0));
                                else
                                    memAAddr                        <= sp;
                                    memAWrite(wordSize-1 downto 7)  <= memARead(wordSize-8 downto 0);
                                    memAWrite(6 downto 0)           <= unsigned(opcode(6 downto 0));
                                end if;
                            when Decoded_StoreSP =>
                                memBWriteEnable                     <= '1';
                                memBAddr                            <= sp+spOffset;
                                memBWrite                           <= memARead;
                                sp                                  <= sp + 1;
                                state                               <= State_Resync;
                            when Decoded_LoadSP =>
                                sp                                  <= sp - 1;
                                memAAddr                            <= sp+spOffset;
                            when Decoded_Emulate =>
                                sp                                  <= sp - 1;
                                memAWriteEnable                     <= '1';
                                memAAddr                            <= sp - 1;
                                memAWrite                           <= (others => DontCareValue);
                                memAWrite(ADDR_BIT_RANGE)           <= pc + 1;
                                -- The emulate address is:
                                --        98 7654 3210
                                -- 0000 00aa aaa0 0000
                                pc                                  <= (others => '0');
                                pc(9 downto 5)                      <= unsigned(opcode(4 downto 0));
                            when Decoded_AddSP =>
                                memAAddr                            <= sp;
                                memBAddr                            <= sp+spOffset;
                                state                               <= State_AddSP;
                            when Decoded_Break =>
                                report "Break instruction encountered" severity failure;
                                break                               <= '1';
                            when Decoded_PushSP =>
                                memAWriteEnable                     <= '1';
                                memAAddr                            <= sp - 1;
                                sp                                  <= sp - 1;
                                memAWrite                           <= (others => DontCareValue);
                                memAWrite(ADDR_32BIT_RANGE)         <= sp;
                            when Decoded_PopPC =>
                                pc                                  <= memARead(ADDR_BIT_RANGE);
                                sp                                  <= sp + 1;
                                state                               <= State_Resync;
                            when Decoded_Add =>
                                sp                                  <= sp + 1;
                                state                               <= State_Add;
                            when Decoded_Or =>
                                sp                                  <= sp + 1;
                                state                               <= State_Or;
                            when Decoded_And =>
                                sp                                  <= sp + 1;
                                state                               <= State_And;
                            when Decoded_Load =>
                                if (memARead(ioBit)='1') then
                                    out_mem_addr                    <= std_logic_vector(memARead(ADDR_BIT_RANGE));
                                    out_mem_readEnable              <= '1';
                                    state                           <= State_ReadIO;
                                else 
                                    memAAddr                        <= memARead(ADDR_32BIT_RANGE);
                                end if;
                            when Decoded_Not =>
                                memAAddr                            <= sp(ADDR_32BIT_RANGE);
                                memAWriteEnable                     <= '1';
                                memAWrite                           <= not memARead;
                            when Decoded_Flip =>
                                memAAddr                            <= sp(ADDR_32BIT_RANGE);
                                memAWriteEnable                     <= '1';
                                for i in 0 to wordSize-1 loop
                                    memAWrite(i)                    <= memARead(wordSize-1-i);
                                  end loop;
                            when Decoded_Store =>
                                memBAddr                            <= sp + 1;
                                sp                                  <= sp + 1;
                                if (memARead(ioBit)='1') then
                                    state                           <= State_WriteIO;
                                else
                                    state                           <= State_Store;
                                end if;
                            when Decoded_PopSP =>
                                sp                                  <= memARead(ADDR_32BIT_RANGE);
                                state                               <= State_Resync;
                            when Decoded_Nop =>    
                                memAAddr                            <= sp;
                            when others =>    
                                null; 
                        end case;
                    when State_ReadIO =>
                        memAAddr                                    <= sp;
                        if (in_mem_busy = '0') then
                            state                                   <= State_Fetch;
                            memAWriteEnable                         <= '1';
                            memAWrite                               <= unsigned(mem_read);
                        end if;
                    when State_WriteIO =>
                        sp                                          <= sp + 1;
                        out_mem_writeEnable                         <= '1';
                        out_mem_addr                                <= std_logic_vector(memARead(ADDR_BIT_RANGE));
                        mem_write                                   <= std_logic_vector(memBRead);
                        state                                       <= State_WriteIODone;
                    when State_WriteIODone =>
                        if (in_mem_busy = '0') then
                            state                                   <= State_Resync;
                        end if;
                    when State_Fetch =>
                        -- We need to resync. During the *next* cycle
                        -- we'll fetch the opcode @ pc and thus it will
                        -- be available for State_Execute the cycle after
                        -- next
                        memBAddr                                    <= pc(ADDR_32BIT_RANGE);
                        state                                       <= State_FetchNext;
                    when State_FetchNext =>
                        -- at this point memARead contains the value that is either
                        -- from the top of stack or should be copied to the top of the stack
                        memAWriteEnable                             <= '1';
                        memAWrite                                   <= memARead; 
                        memAAddr                                    <= sp;
                        memBAddr                                    <= sp + 1;
                        state                                       <= State_Decode;

                        -- If debug enabled, write out state during fetch.
                        if DEBUG_CPU = true and DEBUG_LEVEL >= 2 then
                            debugRec.FMT_DATA_PRTMODE               <= "00";
                            debugRec.FMT_PRE_SPACE                  <= '0';
                            debugRec.FMT_POST_SPACE                 <= '0';
                            debugRec.FMT_PRE_CR                     <= '1';
                            debugRec.FMT_POST_CRLF                  <= '1';
                            debugRec.FMT_SPLIT_DATA                 <= "00";
                            debugRec.DATA_BYTECNT                   <= std_logic_vector(to_unsigned(4, 3));
                            debugRec.DATA2_BYTECNT                  <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.DATA3_BYTECNT                  <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.DATA4_BYTECNT                  <= std_logic_vector(to_unsigned(0, 3));
                            debugRec.WRITE_DATA                     <= '1';
                            debugRec.WRITE_DATA2                    <= '0';
                            debugRec.WRITE_DATA3                    <= '0';
                            debugRec.WRITE_DATA4                    <= '0';
                            debugRec.WRITE_OPCODE                   <= '0';
                            debugRec.WRITE_DECODED_OPCODE           <= '0';
                            debugRec.WRITE_PC                       <= '1';
                            debugRec.WRITE_SP                       <= '1';
                            debugRec.WRITE_STACK_TOS                <= '1';
                            debugRec.WRITE_STACK_NOS                <= '1';
                            debugRec.DATA(63 downto 0)              <= X"4645544348000000";
                            debugRec.DATA2(63 downto 0)             <= (others => '0');
                            debugRec.DATA3(63 downto 0)             <= (others => '0');
                            debugRec.DATA4(63 downto 0)             <= (others => '0');
                            debugRec.OPCODE                         <= (others => '0');
                            debugRec.DECODED_OPCODE                 <= (others => '0');
                            debugRec.PC(ADDR_BIT_RANGE)             <= std_logic_vector(pc);
                            debugRec.SP(ADDR_32BIT_RANGE)           <= std_logic_vector(sp);
                            debugRec.STACK_TOS                      <= std_logic_vector(memARead);
                            debugRec.STACK_NOS                      <= std_logic_vector(memBRead);
                            debugLoad                               <= '1';
                        end if;                        
                    when State_Decode =>
                        if interrupt_request='1' and inInterrupt='0' and idim_flag='0' then
                            -- We got an interrupt, execute interrupt instead of next instruction
                            inInterrupt                             <= '1';
                            decodedOpcode                           <= Decoded_Interrupt;
                        end if;
                        -- during the State_Execute cycle we'll be fetching SP+1
                        memAAddr                                    <= sp;
                        memBAddr                                    <= sp + 1;
                        state                                       <= State_Execute;
                    when State_Store =>
                        sp                                          <= sp + 1;
                        memAWriteEnable                             <= '1';
                        memAAddr                                    <= memARead(ADDR_32BIT_RANGE);
                        memAWrite                                   <= memBRead;
                        state                                       <= State_Resync;
                    when State_AddSP =>
                        state                                       <= State_Add;
                    when State_Add =>
                        memAAddr                                    <= sp;
                        memAWriteEnable                             <= '1';
                        memAWrite                                   <= memARead + memBRead;
                        state                                       <= State_Fetch;
                    when State_Or =>
                        memAAddr                                    <= sp;
                        memAWriteEnable                             <= '1';
                        memAWrite                                   <= memARead or memBRead;
                        state                                       <= State_Fetch;
                    when State_Resync =>
                        memAAddr                                    <= sp;
                        state                                       <= State_Fetch;
                    when State_And =>
                        memAAddr                                    <= sp;
                        memAWriteEnable                             <= '1';
                        memAWrite                                   <= memARead and memBRead;
                        state                                       <= State_Fetch;
                    when State_Debug =>
                        case debugState is
                            when Debug_Start =>
    
                                -- Write out the primary data.
                                if DEBUG_CPU = true then
                                    debugRec.FMT_DATA_PRTMODE       <= "00";
                                    debugRec.FMT_PRE_SPACE          <= '0';
                                    debugRec.FMT_POST_SPACE         <= '0';
                                    debugRec.FMT_PRE_CR             <= '1';
                                    debugRec.FMT_POST_CRLF          <= '0';
                                    debugRec.FMT_SPLIT_DATA         <= "00";
                                    debugRec.DATA_BYTECNT           <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA2_BYTECNT          <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA3_BYTECNT          <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA4_BYTECNT          <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.WRITE_DATA             <= '0';
                                    debugRec.WRITE_DATA2            <= '0';
                                    debugRec.WRITE_DATA3            <= '0';
                                    debugRec.WRITE_DATA4            <= '0';
                                    debugRec.WRITE_OPCODE           <= '0';
                                    debugRec.WRITE_DECODED_OPCODE   <= '0';
                                    debugRec.WRITE_PC               <= '1';
                                    debugRec.WRITE_SP               <= '1';
                                    debugRec.WRITE_STACK_TOS        <= '1';
                                    debugRec.WRITE_STACK_NOS        <= '1';
                                    debugRec.DATA(63 downto 0)      <= (others => '0');
                                    debugRec.DATA2(63 downto 0)     <= (others => '0');
                                    debugRec.DATA3(63 downto 0)     <= (others => '0');
                                    debugRec.DATA4(63 downto 0)     <= (others => '0');
                                    debugRec.OPCODE                 <= (others => '0');
                                    debugRec.DECODED_OPCODE         <= (others => '0');
                                    debugRec.PC(ADDR_BIT_RANGE)     <= std_logic_vector(pc);
                                    debugRec.SP(ADDR_32BIT_RANGE)   <= std_logic_vector(sp);
                                    debugRec.STACK_TOS              <= std_logic_vector(memARead);
                                    debugRec.STACK_NOS              <= std_logic_vector(memBRead);
                                    debugLoad                       <= '1';
                                    debugCnt                        <= 0;
                                    debugState                      <= Debug_DumpFifo;
                                end if;
    
                            when Debug_DumpFifo =>
                                -- Write out the opcode.
                                if DEBUG_CPU = true then
                                    debugRec.FMT_DATA_PRTMODE       <= "00";
                                    debugRec.FMT_PRE_SPACE          <= '0';
                                    debugRec.FMT_POST_SPACE         <= '1';
                                    debugRec.FMT_PRE_CR             <= '0';
                                    if debugCnt = 3 then
                                        debugRec.FMT_POST_CRLF      <= '1';
                                    else
                                        debugRec.FMT_POST_CRLF      <= '0';
                                    end if;
                                    debugRec.FMT_SPLIT_DATA         <= "00";
                                    debugRec.DATA_BYTECNT           <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA2_BYTECNT          <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA3_BYTECNT          <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.DATA4_BYTECNT          <= std_logic_vector(to_unsigned(0, 3));
                                    debugRec.WRITE_DATA             <= '0';
                                    debugRec.WRITE_DATA2            <= '0';
                                    debugRec.WRITE_DATA3            <= '0';
                                    debugRec.WRITE_DATA4            <= '0';
                                    debugRec.WRITE_OPCODE           <= '1';
                                    debugRec.WRITE_DECODED_OPCODE   <= '1';
                                    debugRec.WRITE_PC               <= '0';
                                    debugRec.WRITE_SP               <= '0';
                                    debugRec.WRITE_STACK_TOS        <= '0';
                                    debugRec.WRITE_STACK_NOS        <= '0';
                                    debugRec.DATA(63 downto 0)      <= (others => '0');
                                    debugRec.DATA2(63 downto 0)     <= (others => '0');
                                    debugRec.DATA3(63 downto 0)     <= (others => '0');
                                    debugRec.DATA4(63 downto 0)     <= (others => '0');
                                    debugRec.OPCODE                 <= opcode;
                                    debugRec.DECODED_OPCODE         <= std_logic_vector(to_unsigned(DecodedOpcodeType'POS(decodedOpcode), 6));
                                    debugRec.PC(ADDR_BIT_RANGE)     <= (others => '0');
                                    debugRec.SP(ADDR_32BIT_RANGE)   <= std_logic_vector(sp);
                                    debugRec.STACK_TOS              <= (others => '0');
                                    debugRec.STACK_NOS              <= (others => '0');
                                    debugLoad                       <= '1';
                                    debugCnt                        <= 0;
                                    debugState                      <= Debug_DumpFifo_1;
                                end if;
    
                            when Debug_DumpFifo_1 =>
                                -- Move onto next opcode in Fifo.
                                debugCnt                            <= debugCnt + 1;
                                if debugCnt = 3 then
                                    debugState                      <= Debug_End;
                                else
                                    debugState                      <= Debug_DumpFifo;
                                end if;
    
                            when Debug_End =>
                                state                               <= State_Execute;
                        end case;
                    when others =>
                        null;
                end case;
            end if;
        end if;
    end process;

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
                CLK                      => clk,                             -- master clock
                RESET                    => areset,                          -- high active sync reset
                DEBUG_DATA               => debugRec,                        -- write data
                CS                       => debugLoad,                       -- Chip Select.
                READY                    => debugReady,                      -- Debug processor ready for next command.
    
                -- Serial data
                TXD                      => debug_txd
            );
    end generate;
    -----------------------------------------------------------------------------------------------------------------------------------------------------------
    -- End of debugger output processor.
    -----------------------------------------------------------------------------------------------------------------------------------------------------------

end behave;
