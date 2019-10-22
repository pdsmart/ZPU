---------------------------------------------------------------------------------------------------------
--
-- Name:            sram.vhd
-- Created:         September 2019
-- Author(s):       Philip Smart
-- Description:     WishBone encapsulation of BRAM memory.
--                                                     
-- Credits:         
-- Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
--
-- History:         September 2019 - Initial creation.
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

entity SRAM is
    generic (
        addrbits      : integer := 16                                   -- Size, in bits (representing bytes), of total memory to allocate.
    );
    port (
        -- Wishbone Bus --
        WB_CLK_I      : in  std_logic;                                  -- WishBone master clock
        WB_RST_I      : in  std_logic;                                  -- high active sync reset
        WB_CYC_I      : in  std_logic;
        WB_TGC_I      : in  std_logic_vector(06 downto 0);              -- cycle tag
        WB_ADR_I      : in  std_logic_vector(addrbits-1 downto 0);      -- adr in
        WB_DATA_I     : in  std_logic_vector(31 downto 0);              -- write data
        WB_DATA_O     : out std_logic_vector(31 downto 0);              -- read data
        WB_SEL_I      : in  std_logic_vector(03 downto 0);              -- data quantity
        WB_WE_I       : in  std_logic;                                  -- write enable
        WB_STB_I      : in  std_logic;                                  -- valid cycle
        WB_ACK_O      : out std_logic;                                  -- acknowledge
        WB_CTI_I      : in  std_logic_vector(2 downto 0);               -- 000 Classic cycle, 001 Constant address burst cycle, 010 Incrementing burst cycle, 111 End-of-Burst
        WB_HALT_O     : out std_logic;                                  -- throttle master
        WB_ERR_O      : out std_logic                                   -- abnormal cycle termination
    );
end SRAM;

architecture Behavioral of SRAM is

    --- Muxed ACK signal.
    signal WB_ACK_O_INT : std_logic;

    -- Define memory as an array of 4x8bit blocks to allow for individual byte write/read.
    type ramArray is array(natural range 0 to (2**(addrbits-2))-1) of std_logic_vector(7 downto 0);

    shared variable RAM0 : ramArray :=
    (
        others => x"AA"
    );
    shared variable RAM1 : ramArray :=
    (
        others => x"55"
    );
    shared variable RAM2 : ramArray :=
    (
        others => x"AA"
    );
    shared variable RAM3 : ramArray :=
    (
        others => x"55"
    );

begin

    -- RAM Byte 0 - bits 7 to 0
    process(WB_CLK_I)
    begin
        if rising_edge(WB_CLK_I) then
            if WB_WE_I = '1' and WB_STB_I = '1' and WB_SEL_I(0) = '1' then
                RAM0(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2)))) := WB_DATA_I(7 downto 0);
            else
                WB_DATA_O(7 downto 0) <= RAM0(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- RAM Byte 1 - bits 15 to 8
    process(WB_CLK_I)
    begin
        if rising_edge(WB_CLK_I) then
            if WB_WE_I = '1' and WB_STB_I = '1' and WB_SEL_I(1) = '1' then
                RAM1(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2)))) := WB_DATA_I(15 downto 8);
            else
                WB_DATA_O(15 downto 8) <= RAM1(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- RAM Byte 2 - bits 23 to 16 
    process(WB_CLK_I)
    begin
        if rising_edge(WB_CLK_I) then
            if WB_WE_I = '1' and WB_STB_I = '1' and WB_SEL_I(2) = '1' then
                RAM2(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2)))) := WB_DATA_I(23 downto 16);
            else
                WB_DATA_O(23 downto 16) <= RAM2(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- RAM Byte 3 - bits 31 to 24 
    process(WB_CLK_I)
    begin
        if rising_edge(WB_CLK_I) then
            if WB_WE_I = '1' and WB_STB_I = '1' and WB_SEL_I(3) = '1' then
                RAM3(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2)))) := WB_DATA_I(31 downto 24);
            else
                WB_DATA_O(31 downto 24) <= RAM3(to_integer(unsigned(WB_ADR_I(addrbits-1 downto 2))));
            end if;
        end if;
    end process;

    -- WishBone control.
    WISHBONECTL: process(WB_CLK_I)
    begin
        if rising_edge(WB_CLK_I) then

            --- ACK Control
            if (WB_RST_I = '1') then
                WB_ACK_O_INT <= '0';
            elsif (WB_CTI_I = "000") or (WB_CTI_I = "111") then
                WB_ACK_O_INT <= WB_STB_I and (not WB_ACK_O_INT);
            else
                WB_ACK_O_INT <= WB_STB_I;
            end if;

        end if;
    end process;

    --- ACK Signal
    WB_ACK_O  <= WB_ACK_O_INT;

    --- Throttle
    WB_HALT_O <= '0';

    --- Error
    WB_ERR_O  <= '0';

end Behavioral;
