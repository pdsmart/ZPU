-- Byte Addressed 32bit BRAM module for the ZPU Evo implementation.
--
-- Copyright 2018-2019 - Philip Smart for the ZPU Evo implementation.
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

entity SinglePortBRAM is
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
        memARead             : out std_logic_vector(WORD_32BIT_RANGE)
    );
end SinglePortBRAM;

architecture arch of SinglePortBRAM is

    type ramArray is array(natural range 0 to (2**(addrbits-2))-1) of std_logic_vector(7 downto 0);

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

    signal RAM0_DATA                       : std_logic_vector(7 downto 0);   -- Buffer for byte in word to be written.
    signal RAM1_DATA                       : std_logic_vector(7 downto 0);   -- Buffer for byte in word to be written.
    signal RAM2_DATA                       : std_logic_vector(7 downto 0);   -- Buffer for byte in word to be written.
    signal RAM3_DATA                       : std_logic_vector(7 downto 0);   -- Buffer for byte in word to be written.
    signal RAM0_WREN                       : std_logic;                      -- Write Enable for this particular byte in word.
    signal RAM1_WREN                       : std_logic;                      -- Write Enable for this particular byte in word.
    signal RAM2_WREN                       : std_logic;                      -- Write Enable for this particular byte in word.
    signal RAM3_WREN                       : std_logic;                      -- Write Enable for this particular byte in word.

begin

    RAM0_DATA <= memAWrite(7 downto 0);
    RAM1_DATA <= memAWrite(15 downto 8)  when (memAWriteByte = '0' and memAWriteHalfWord = '0') or memAWriteHalfWord = '1'
                 else
                 memAWrite(7 downto 0);
    RAM2_DATA <= memAWrite(23 downto 16) when (memAWriteByte = '0' and memAWriteHalfWord = '0')
                 else
                 memAWrite(7 downto 0);
    RAM3_DATA <= memAWrite(31 downto 24) when (memAWriteByte = '0' and memAWriteHalfWord = '0')
                 else
                 memAWrite(15 downto 8)  when memAWriteHalfWord = '1'
                 else
                 memAWrite(7 downto 0);

    RAM0_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0') or (memAWriteByte = '1' and memAAddr(1 downto 0) = "11") or (memAWriteHalfWord = '1' and memAAddr(1) = '1'))
                 else '0';
    RAM1_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0') or (memAWriteByte = '1' and memAAddr(1 downto 0) = "10") or (memAWriteHalfWord = '1' and memAAddr(1) = '1'))
                 else '0';
    RAM2_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0') or (memAWriteByte = '1' and memAAddr(1 downto 0) = "01") or (memAWriteHalfWord = '1' and memAAddr(1) = '0'))
                 else '0';
    RAM3_WREN <= '1' when memAWriteEnable = '1' and ((memAWriteByte = '0' and memAWriteHalfWord = '0') or (memAWriteByte = '1' and memAAddr(1 downto 0) = "00") or (memAWriteHalfWord = '1' and memAAddr(1) = '0'))
                 else '0';

    -- RAM Byte 0 - Port A - bits 7 to 0
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM0_WREN = '1' then
                RAM0(to_integer(unsigned(memAAddr(addrbits-1 downto 2)))) := RAM0_DATA;
            else
                memARead(7 downto 0) <= RAM0(to_integer(unsigned(memAAddr(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- RAM Byte 1 - Port A - bits 15 to 8
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM1_WREN = '1' then
                RAM1(to_integer(unsigned(memAAddr(addrbits-1 downto 2)))) := RAM1_DATA;
            else
                memARead(15 downto 8) <= RAM1(to_integer(unsigned(memAAddr(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- RAM Byte 2 - Port A - bits 23 to 16 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM2_WREN = '1' then
                RAM2(to_integer(unsigned(memAAddr(addrbits-1 downto 2)))) := RAM2_DATA;
            else
                memARead(23 downto 16) <= RAM2(to_integer(unsigned(memAAddr(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- RAM Byte 3 - Port A - bits 31 to 24 
    process(clk)
    begin
        if rising_edge(clk) then
            if RAM3_WREN = '1' then
                RAM3(to_integer(unsigned(memAAddr(addrbits-1 downto 2)))) := RAM3_DATA;
            else
                memARead(31 downto 24) <= RAM3(to_integer(unsigned(memAAddr(addrbits-1 downto 2))));
            end if;
        end if;
    end process;
end arch;
