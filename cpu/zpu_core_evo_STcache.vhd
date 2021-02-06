-- 32bit Word Addressed BRAM module for the ZPU Evo implementation.
--
-- This memory is used for the stack cache. It has 64bit wide read/
-- write for the CPU side which represents TOS/NOS and 32bit wide
-- read/write for the interface between the MXP and the external memory.
--
-- Copyright 2018-2021 - Philip Smart for the ZPU Evo implementation.
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
library pkgs;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.zpu_pkg.all;
use work.zpu_soc_pkg.all;

entity evo_STcache is
    generic
    (
        addrbits             : integer := 16
    );
    port
    (
        clk                  : in  std_logic;
        memAAddr             : in  std_logic_vector(addrbits-1 downto 2);
        memAWriteTOSEnable   : in  std_logic;
        memAWriteNOSEnable   : in  std_logic;
        memAWrite            : in  std_logic_vector(WORD_64BIT_RANGE);
        memARead             : out std_logic_vector(WORD_64BIT_RANGE);

        memBAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memBWriteEnable      : in  std_logic;
        memBWriteByte        : in  std_logic;
        memBWriteHalfWord    : in  std_logic;
        memBWrite            : in  std_logic_vector(WORD_32BIT_RANGE);
        memBRead             : out std_logic_vector(WORD_32BIT_RANGE)
    );
end evo_STcache;

architecture arch of evo_STcache is

    type ramArray is array(natural range 0 to (2**(addrbits-2))-1) of std_logic_vector(7 downto 0);

    shared variable RAMTOS0 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS1 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS2 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS3 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS4 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS5 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS6 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMTOS7 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAMNOS0 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS1 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS2 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS3 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS4 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS5 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS6 : ramArray :=
    (
        others => X"00"
    );
    shared variable RAMNOS7 : ramArray :=
    (
        others => X"00"
    );

    signal TOSreadA                        : std_logic_vector(WORD_32BIT_RANGE);        -- Buffer for reading a 64bit TOS word.
    signal NOSreadA                        : std_logic_vector(WORD_32BIT_RANGE);        -- Buffer for reading a 64bit NOS word.
    signal TOSreadB                        : std_logic_vector(WORD_32BIT_RANGE);        -- Buffer for reading a 32bit TOS word.
    signal NOSreadB                        : std_logic_vector(WORD_32BIT_RANGE);        -- Buffer for reading a 32bit NOS word.
    signal RAMTOS_A_ADDR                   : unsigned(addrbits-1 downto 2);             -- Address on Port A to read/write TOS from.
    signal RAMNOS_A_ADDR                   : unsigned(addrbits-1 downto 2);             -- Address on Port B to read/write NOS from.
    signal RAMTOS0_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMTOS1_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMTOS2_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMTOS3_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMNOS0_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMNOS1_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMNOS2_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMNOS3_B_DATA                  : std_logic_vector(WORD_8BIT_RANGE);         -- Buffer for selecting correct part of a 32bit word to be written in bytes.
    signal RAMTOS_A_WREN                   : std_logic;                                 -- Write Enable for the TOS word on the A Port.
    signal RAMNOS_A_WREN                   : std_logic;                                 -- Write Enable for the NOS word on the A Port.
    signal RAMTOS0_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the TOS word on the B Port.
    signal RAMTOS1_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the TOS word on the B Port.
    signal RAMTOS2_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the TOS word on the B Port.
    signal RAMTOS3_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the TOS word on the B Port.
    signal RAMNOS0_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the NOS word on the B Port.
    signal RAMNOS1_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the NOS word on the B Port.
    signal RAMNOS2_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the NOS word on the B Port.
    signal RAMNOS3_B_WREN                  : std_logic;                                 -- Write Enable for one byte of the NOS word on the B Port.

begin

    -- Signal processing. memARead is 64bit so combine the two arrays according to the LSB, memBRead is 32 bit so mux the correct word.
    -- memAWrite is 64bit so write the given long word direct for even addresses or across 2 addresses if address is odd, memBWrite is 32bit so select the correct word to write.
    memARead       <= NOSreadA & TOSreadA;
    memBRead       <= TOSreadB  when memBAddr(2) = '1'
                      else
                      NOSreadB;
    RAMTOS_A_WREN  <= '1'       when memAWriteTOSEnable = '1' and memAAddr(2) = '0'
                      else
                      '1'       when memAWriteNOSEnable = '1' and memAAddr(2) = '1'
                      else '0';
    RAMNOS_A_WREN  <= '1'       when memAWriteNOSEnable = '1' and memAAddr(2) = '0'
                      else
                      '1'       when memAWriteNOSEnable = '1' and memAAddr(2) = '1'
                      else '0';
    RAMTOS_A_ADDR  <= unsigned(memAAddr(addrbits-1 downto 2)) when memAAddr(2) = '0'
                      else
                      unsigned(memAAddr(addrbits-1 downto 2))-1;
    RAMNOS_A_ADDR  <= unsigned(memAAddr(addrbits-1 downto 2));

    RAMTOS0_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '0') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "011") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "01"))
                      else '0';
    RAMTOS1_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '0') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "010") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "01"))
                      else '0';
    RAMTOS2_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '0') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "001") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "00"))
                      else '0';
    RAMTOS3_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '0') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "000") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "00"))
                      else '0';
    RAMNOS0_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '1') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "111") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "11"))
                      else '0';
    RAMNOS1_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '1') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "110") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "11"))
                      else '0';
    RAMNOS2_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '1') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "101") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "10"))
                      else '0';
    RAMNOS3_B_WREN <= '1' when memBWriteEnable = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0' and memBAddr(2) = '1') or (memBWriteByte = '1' and memBAddr(2 downto 0) = "100") or (memBWriteHalfWord = '1' and memBAddr(2 downto 1) = "10"))
                      else '0';

    RAMTOS0_B_DATA <= memBWrite(7 downto 0)   when memBAddr(2) = '0'
                      else (others => '0');
    RAMTOS1_B_DATA <= memBWrite(15 downto 8)  when memBAddr(2) = '0' and ((memBWriteByte = '0' and memBWriteHalfWord = '0') or memBWriteHalfWord = '1')
                      else
                      memBWrite(7 downto 0);
    RAMTOS2_B_DATA <= memBWrite(23 downto 16) when memBAddr(2) = '0' and ((memBWriteByte = '0' and memBWriteHalfWord = '0'))
                      else
                      memBWrite(7 downto 0);
    RAMTOS3_B_DATA <= memBWrite(31 downto 24) when memBAddr(2) = '0' and ((memBWriteByte = '0' and memBWriteHalfWord = '0'))
                      else
                      memBWrite(15 downto 8)  when memBAddr(2) = '0' and (memBWriteHalfWord = '1')
                      else
                      memBWrite(7 downto 0);
    RAMNOS0_B_DATA <= memBWrite(7 downto 0)   when memBAddr(2) = '1'
                      else (others => '0');
    RAMNOS1_B_DATA <= memBWrite(15 downto 8)  when memBAddr(2) = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0') or memBWriteHalfWord = '1')
                      else
                      memBWrite(7 downto 0);
    RAMNOS2_B_DATA <= memBWrite(23 downto 16) when memBAddr(2) = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0'))
                      else
                      memBWrite(7 downto 0);
    RAMNOS3_B_DATA <= memBWrite(31 downto 24) when memBAddr(2) = '1' and ((memBWriteByte = '0' and memBWriteHalfWord = '0'))
                      else
                      memBWrite(15 downto 8)  when memBAddr(2) = '1' and (memBWriteHalfWord = '1')
                      else
                      memBWrite(7 downto 0);


    ----------------------------------------
    -- Port A - 64bit wide.
    -- Word addressable.
    ----------------------------------------

    -- RAM Port A - TOS - bits 7 to 0 (7 downto 0 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS_A_WREN = '1' then
                RAMTOS0(to_integer(RAMTOS_A_ADDR)) := memAWrite(7 downto 0);
                TOSreadA(7 downto 0)   <= memAWrite(7 downto 0);
            else
                TOSreadA(7 downto 0)   <= RAMTOS0(to_integer(RAMTOS_A_ADDR)); 
            end if;
        end if;
    end process;

    -- RAM Port A - TOS - bits 15 to 8 (15 downto 8 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS_A_WREN = '1' then
                RAMTOS1(to_integer(RAMTOS_A_ADDR)) := memAWrite(15 downto 8);
                TOSreadA(15 downto 8)  <= memAWrite(15 downto 8);
            else
                TOSreadA(15 downto 8)  <= RAMTOS1(to_integer(RAMTOS_A_ADDR)); 
            end if;
        end if;
    end process;

    -- RAM Port A - TOS - bits 23 to 16 (23 downto 16 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS_A_WREN = '1' then
                RAMTOS2(to_integer(RAMTOS_A_ADDR)) := memAWrite(23 downto 16);
                TOSreadA(23 downto 16) <= memAWrite(23 downto 16);
            else
                TOSreadA(23 downto 16) <= RAMTOS2(to_integer(RAMTOS_A_ADDR)); 
            end if;
        end if;
    end process;

    -- RAM Port A - TOS - bits 31 to 24 (31 downto 24 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS_A_WREN = '1' then
                RAMTOS3(to_integer(RAMTOS_A_ADDR)) := memAWrite(31 downto 24);
                TOSreadA(31 downto 24) <= memAWrite(31 downto 24);
            else
                TOSreadA(31 downto 24) <= RAMTOS3(to_integer(RAMTOS_A_ADDR)); 
            end if;
        end if;
    end process;

    -- RAM Port A - NOS - bits 7 to 0 (39 downto 32 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS_A_WREN = '1' then
                RAMNOS0(to_integer(RAMNOS_A_ADDR)) := memAWrite(39 downto 32);
                NOSreadA(7 downto 0)   <= memAWrite(39 downto 32);
            else
                NOSreadA(7 downto 0)   <= RAMNOS0(to_integer(RAMNOS_A_ADDR));
            end if;
        end if;
    end process;

    -- RAM Port A - NOS - bits 15 to 8 (47 downto 40 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS_A_WREN = '1' then
                RAMNOS1(to_integer(RAMNOS_A_ADDR)) := memAWrite(47 downto 40);
                NOSreadA(15 downto 8)  <= memAWrite(47 downto 40);
            else
                NOSreadA(15 downto 8)  <= RAMNOS1(to_integer(RAMNOS_A_ADDR));
            end if;
        end if;
    end process;

    -- RAM Port A - NOS - bits 23 to 16 (55 downto 48 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS_A_WREN = '1' then
                RAMNOS2(to_integer(RAMNOS_A_ADDR)) := memAWrite(55 downto 48);
                NOSreadA(23 downto 16) <= memAWrite(55 downto 48);
            else
                NOSreadA(23 downto 16) <= RAMNOS2(to_integer(RAMNOS_A_ADDR));
            end if;
        end if;
    end process;

    -- RAM Port A - NOS - bits 31 to 24 (63 downto 56 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS_A_WREN = '1' then
                RAMNOS3(to_integer(RAMNOS_A_ADDR)) := memAWrite(63 downto 56);
                NOSreadA(31 downto 24) <= memAWrite(63 downto 56);
            else
                NOSreadA(31 downto 24) <= RAMNOS3(to_integer(RAMNOS_A_ADDR));
            end if;
        end if;
    end process;

    ----------------------------------------
    -- Port B - 32bit wide.
    -- Byte addressable.
    ----------------------------------------

    -- RAM Port B - TOS - bits 7 downto 0 (7 downto 0 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS0_B_WREN = '1' then
                RAMTOS0(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMTOS0_B_DATA;
                TOSreadB(7 downto 0)   <= RAMTOS0_B_DATA;
            else
                TOSreadB(7 downto 0)   <= RAMTOS0(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - TOS - bits 15 downto 8 (15 downto 8 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS1_B_WREN = '1' then
                RAMTOS1(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMTOS1_B_DATA;
                TOSreadB(15 downto 8)  <= RAMTOS1_B_DATA;
            else
                TOSreadB(15 downto 8)  <= RAMTOS1(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - TOS - bits 23 downto 16 (23 downto 16 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS2_B_WREN = '1' then
                RAMTOS2(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMTOS2_B_DATA;
                TOSreadB(23 downto 16) <= RAMTOS2_B_DATA;
            else
                TOSreadB(23 downto 16) <= RAMTOS2(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - TOS - bits 31 downto 24 (31 downto 24 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMTOS3_B_WREN = '1' then
                RAMTOS3(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMTOS3_B_DATA;
                TOSreadB(31 downto 24) <= RAMTOS3_B_DATA;
            else
                TOSreadB(31 downto 24) <= RAMTOS3(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - NOS - bits 7 downto 0 (39 downto 32 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS0_B_WREN = '1' then
                RAMNOS0(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMNOS0_B_DATA;
                NOSreadB(7 downto 0)   <= RAMNOS0_B_DATA;
            else
                NOSreadB(7 downto 0)   <= RAMNOS0(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - NOS - bits 15 downto 8 (47 downto 40 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS1_B_WREN = '1' then
                RAMNOS1(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMNOS1_B_DATA;
                NOSreadB(15 downto 8)  <= RAMNOS1_B_DATA;
            else
                NOSreadB(15 downto 8)  <= RAMNOS1(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - NOS - bits 23 downto 16 (55 downto 48 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS2_B_WREN = '1' then
                RAMNOS2(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMNOS2_B_DATA;
                NOSreadB(23 downto 16) <= RAMNOS2_B_DATA;
            else
                NOSreadB(23 downto 16) <= RAMNOS2(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Port B - NOS - bits 31 downto 24 (63 downto 56 in 64bit word).
    process(clk)
    begin
        if rising_edge(clk) then
            if RAMNOS3_B_WREN = '1' then
                RAMNOS3(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := RAMNOS3_B_DATA;
                NOSreadB(31 downto 24) <= RAMNOS3_B_DATA;
            else
                NOSreadB(31 downto 24) <= RAMNOS3(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;
end arch;
