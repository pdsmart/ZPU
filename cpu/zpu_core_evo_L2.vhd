-- Byte Addressed 32bit BRAM module for the ZPU Evo implementation.
--
-- Copyright 2018-2021 - Philip Smart for the ZPU Evo implementation.
-- History:
-- 20190618  - Initial 32 bit version of the cache using inference rather than IP Megacore packages.
-- 20210108  - Updated to 64bit, 32 bit Read/Write on Port A, 64bit Read/Write on Port B. This
--             change is to increase throughput on the cache decoder.
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

library ieee;
library pkgs;
library work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.zpu_pkg.all;
--use work.zpu_soc_pkg.all;

entity evo_L2cache is
    generic
    (
        addrbits             : integer := 16
    );
    port
    (
        clk                  : in  std_logic;
        memAAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memAWriteEnable      : in  std_logic;
        memAWriteByte        : in  std_logic;
        memAWriteHalfWord    : in  std_logic;
        memAWrite            : in  std_logic_vector(WORD_32BIT_RANGE);
        memARead             : out std_logic_vector(WORD_32BIT_RANGE);

        memBAddr             : in  std_logic_vector(addrbits-1 downto 3);
        memBWrite            : in  std_logic_vector(WORD_64BIT_RANGE);
        memBWriteEnable      : in  std_logic;
        memBRead             : out std_logic_vector(WORD_64BIT_RANGE)
    );
end evo_L2cache;

architecture arch of evo_L2cache is

    -- Declare 8 byte wide arrays for byte level addressing.
    type ramArray is array(natural range 0 to (2**(addrbits-3))-1) of std_logic_vector(7 downto 0);

    shared variable RAM0 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM1 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM2 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM3 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM4 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM5 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM6 : ramArray :=
    (
        others => X"00"
    );

    shared variable RAM7 : ramArray :=
    (
        others => X"00"
    );

    signal RAM0_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM1_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM2_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM3_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM4_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM5_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM6_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM7_DATA         :     std_logic_vector(7 downto 0);         -- Buffer for byte in word to be written.
    signal RAM0_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM1_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM2_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM3_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM4_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM5_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM6_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal RAM7_WREN         :     std_logic;                            -- Write Enable for this particular byte in word.
    signal lowDataA          :     std_logic_vector(WORD_32BIT_RANGE);   -- Low word in 64 bit output from RAM matrix.
    signal highDataA         :     std_logic_vector(WORD_32BIT_RANGE);   -- High word in 64 bit output from RAM matrix.
    signal lowDataB          :     std_logic_vector(WORD_32BIT_RANGE);   -- Low word in 64 bit output from RAM matrix.
    signal highDataB         :     std_logic_vector(WORD_32BIT_RANGE);   -- High word in 64 bit output from RAM matrix.

begin

    -- Correctly assign the Little Endian value to the correct array, byte writes the data is in '7 downto 0', h-word writes
    -- the data is in '15 downto 0', word writes the data is in '31 downto 0'. Long words (64bits) are treated as two words for Endianness,
    -- and not as one continuous long word, this is because the ZPU is 32bit even when accessing a 64bit chunk.
    --
    RAM0_DATA <= memAWrite(7 downto 0)   when memAAddr(2) = '0'
                 else (others => '0');
    RAM1_DATA <= memAWrite(15 downto 8)  when memAAddr(2) = '0' and ((memAWriteByte = '0' and memAWriteHalfWord = '0') or memAWriteHalfWord = '1')
                 else
                 memAWrite(7 downto 0);
    RAM2_DATA <= memAWrite(23 downto 16) when memAAddr(2) = '0' and ((memAWriteByte = '0' and memAWriteHalfWord = '0'))
                 else
                 memAWrite(7 downto 0);
    RAM3_DATA <= memAWrite(31 downto 24) when memAAddr(2) = '0' and ((memAWriteByte = '0' and memAWriteHalfWord = '0'))
                 else
                 memAWrite(15 downto 8)  when memAAddr(2) = '0' and (memAWriteHalfWord = '1')
                 else
                 memAWrite(7 downto 0);
    RAM4_DATA <= memAWrite(7 downto 0)   when memAAddr(2) = '1'
                 else (others => '0');
    RAM5_DATA <= memAWrite(15 downto 8)  when memAAddr(2) = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0') or memAWriteHalfWord = '1')
                 else
                 memAWrite(7 downto 0);
    RAM6_DATA <= memAWrite(23 downto 16) when memAAddr(2) = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0'))
                 else
                 memAWrite(7 downto 0);
    RAM7_DATA <= memAWrite(31 downto 24) when memAAddr(2) = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0'))
                 else
                 memAWrite(15 downto 8)  when memAAddr(2) = '1' and (memAWriteHalfWord = '1')
                 else
                 memAWrite(7 downto 0);

    RAM0_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '0') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "011") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "01"))
                 else '0';
    RAM1_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '0') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "010") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "01"))
                 else '0';
    RAM2_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '0') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "001") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "00"))
                 else '0';
    RAM3_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '0') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "000") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "00"))
                 else '0';
    RAM4_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '1') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "111") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "11"))
                 else '0';
    RAM5_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '1') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "110") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "11"))
                 else '0';
    RAM6_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '1') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "101") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "10"))
                 else '0';
    RAM7_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0' and memAAddr(2) = '1') or (memAWriteByte = '1' and memAAddr(2 downto 0) = "100") or (memAWriteHalfWord = '1' and memAAddr(2 downto 1) = "10"))
                 else '0';

    memARead  <= lowDataA  when memAAddr(2) = '0'
                 else
                 highDataA;
    memBRead  <= lowDataB & highDataB;

    -- RAM Byte 0 - Port A - bits 7 to 0
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM0_WREN = '1' then
                RAM0(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM0_DATA;
            else
                lowDataA(7 downto 0)    <= RAM0(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 1 - Port A - bits 15 to 8
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM1_WREN = '1' then
                RAM1(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM1_DATA;
            else
                lowDataA(15 downto 8)   <= RAM1(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 2 - Port A - bits 23 to 16 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM2_WREN = '1' then
                RAM2(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM2_DATA;
            else
                lowDataA(23 downto 16)  <= RAM2(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 3 - Port A - bits 31 to 24 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM3_WREN = '1' then
                RAM3(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM3_DATA;
            else
                lowDataA(31 downto 24)  <= RAM3(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 4 - Port A - bits 39 to 32 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM4_WREN = '1' then
                RAM4(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM4_DATA;
            else
                highDataA(7 downto 0)   <= RAM4(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 5 - Port A - bits 47 to 40 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM5_WREN = '1' then
                RAM5(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM5_DATA;
            else
                highDataA(15 downto 8)  <= RAM5(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 6 - Port A - bits 56 to 48
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM6_WREN = '1' then
                RAM6(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM6_DATA;
            else
                highDataA(23 downto 16) <= RAM6(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- RAM Byte 7 - Port A - bits 63 to 57 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM7_WREN = '1' then
                RAM7(to_integer(unsigned(memAAddr(addrbits-1 downto 3)))) := RAM7_DATA;
            else
                highDataA(31 downto 24) <= RAM7(to_integer(unsigned(memAAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;


    -- BRAM Byte 0 - Port B - bits 7 downto 0
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM0(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(7 downto 0);
                lowDataB(7 downto 0)    <= memBWrite(7 downto 0);
            else
                lowDataB(7 downto 0)    <= RAM0(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 1 - Port B - bits 15 downto 8
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM1(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(15 downto 8);
                lowDataB(15 downto 8)    <= memBWrite(15 downto 8);
            else
                lowDataB(15 downto 8)    <= RAM1(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 2 - Port B - bits 23 downto 16
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM2(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(23 downto 16);
                lowDataB(23 downto 16)  <= memBWrite(23 downto 16);
            else
                lowDataB(23 downto 16)  <= RAM2(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 3 - Port B - bits 31 downto 24
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM3(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(31 downto 24);
                lowDataB(31 downto 24)  <= memBWrite(31 downto 24);
            else
                lowDataB(31 downto 24)  <= RAM3(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 4 - Port B - bits 39 downto 32
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM4(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(39 downto 32);
                highDataB(7 downto 0)   <= memBWrite(39 downto 32);
            else
                highDataB(7 downto 0)   <= RAM4(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 5 - Port B - bits 47 downto 40
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM5(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(47 downto 40);
                highDataB(15 downto 8)  <= memBWrite(47 downto 40);
            else
                highDataB(15 downto 8)  <= RAM5(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 6 - Port B - bits 55 downto 48
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM6(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(55 downto 48);
                highDataB(23 downto 16)  <= memBWrite(55 downto 48);
            else
                highDataB(23 downto 16)  <= RAM6(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

    -- BRAM Byte 7 - Port B - bits 63 downto 56 
    process(clk)
    begin
        if rising_edge(clk) then
            if memBWriteEnable = '1' then
                RAM7(to_integer(unsigned(memBAddr(addrbits-1 downto 3)))) := memBWrite(63 downto 56);
                highDataB(31 downto 24)  <= memBWrite(63 downto 56);
            else
                highDataB(31 downto 24)  <= RAM7(to_integer(unsigned(memBAddr(addrbits-1 downto 3))));
            end if;
        end if;
    end process;

end arch;
