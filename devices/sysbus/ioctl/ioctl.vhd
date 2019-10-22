---------------------------------------------------------------------------------------------------------
--
-- Name:            ioctl.vhd
-- Created:         November 2018
-- Author(s):       Philip Smart
-- Description:     ZPU SOC IOCTL Interface to an Emulator (Sharp MZ series).
--                  This module interfaces the ZPU IO processor to the Emulator IO Control backdoor
--                  for updating ROM/RAM, OSD and providing IO services.
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         November 2019 - Initial module written for STORM Wishbone interface, then adapted to
--                                  work with the ZPU in non-WB direct access.
--                  September 2019- Still needs completion, not yet fully operable.
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

entity IOCTL is
    port (
        -- CPU Interface
        CLK                   : in    std_logic;                                  -- memory master clock
        RESET                 : in    std_logic;                                  -- high active sync reset
        ADDR                  : in    std_logic_vector(2 downto 0);
        DATA_IN               : in    std_logic_vector(31 downto 0);              -- write data
        DATA_OUT              : out   std_logic_vector(31 downto 0);              -- read data
        CS                    : in    std_logic;                                  -- Chip Select.
        WREN                  : in    std_logic;                                  -- Write enable.
        RDEN                  : in    std_logic;                                  -- Read enable.

        -- IRQ outputs --
        IRQ_RD_O              : out   std_logic;
        IRQ_WR_O              : out   std_logic;

        -- IOCTL Bus --
        IOCTL_DOWNLOAD        : out   std_logic;                                  -- Downloading to FPGA.
        IOCTL_UPLOAD          : out   std_logic;                                  -- Uploading from FPGA.
        IOCTL_CLK             : out   std_logic;                                  -- I/O Clock.
        IOCTL_WR              : out   std_logic;                                  -- Write Enable to FPGA.
        IOCTL_RD              : out   std_logic;                                  -- Read Enable from FPGA.
        IOCTL_SENSE           : in    std_logic;                                  -- Sense to see if HPS accessing ioctl bus.
        IOCTL_SELECT          : out   std_logic;                                  -- Enable IOP control over ioctl bus.
        IOCTL_ADDR            : out   std_logic_vector(24 downto 0);              -- Address in FPGA to write into.
        IOCTL_DOUT            : out   std_logic_vector(31 downto 0);              -- Data to be written into FPGA.
        IOCTL_DIN             : in    std_logic_vector(31 downto 0)               -- Data to be read into HPS.
    );
end IOCTL;

architecture Structure of IOCTL is

    -- Constants for register access.
    --
    constant MODE_FG_BLUE     :       integer := 31; 
    constant MODE_FG_RED      :       integer := 30; 
    constant MODE_FG_GREEN    :       integer := 29; 
    constant MODE_BG_BLUE     :       integer := 28; 
    constant MODE_BG_RED      :       integer := 27; 
    constant MODE_BG_GREEN    :       integer := 26; 
    subtype  MODE_ROTATION is integer range 25 downto 24;
    constant MODE_H2X         :       integer := 23; 
    constant MODE_V2X         :       integer := 22; 
    constant MODE_HALFPIXEL   :       integer := 21;
    
    signal DATA_AVAIL         :       std_logic;
    signal WRITE_BUSY         :       std_logic;
    signal WRITE_CHAR_BUSY    :       std_logic;
    signal CLR_RD_CMD         :       std_logic;
    signal CLR_WR_CMD         :       std_logic;
    signal CLR_WR_CHAR_CMD    :       std_logic;
    signal CLR_DATA_AVAIL     :       std_logic;
    signal RD_CMD_STATE       :       integer range 0 to 5;
    signal WR_CMD_STATE       :       integer range 0 to 5;
    signal WR_CHAR_CMD_STATE  :       integer range 0 to 9;
    signal DST_RAM_ADDR       :       std_logic_vector(24 downto 0);
    signal DST_CHAR           :       std_logic_vector(15 downto 0);
    signal DST_HX2            :       std_logic;
    signal DST_VX2            :       std_logic;
    signal CG_BYTE            :       std_logic_vector(7 downto 0);
    signal CG_ROW             :       std_logic_vector(2 downto 0);
    signal REGISTER_CMDADDR   :       std_logic_vector(31 downto 0);
    signal REGISTER_DOUT      :       std_logic_vector(31 downto 0);
    signal REGISTER_DIN       :       std_logic_vector(31 downto 0);
    signal REGISTER_CHRCOLS   :       std_logic_vector(7 downto 0);
    signal REGISTER_CGADDR    :       std_logic_vector(24 downto 0);
    signal CON_IOCTL_WR       :       std_logic;   
    signal CON_IOCTL_RD       :       std_logic;  
    signal CON_IOCTL_SELECT   :       std_logic; 
    
    -- Array to hold a single character for rotation.
    --
    type CGARRAY is array (7 downto 0, 7 downto 0) of std_logic;
    signal CGCHAR             :       CGARRAY;

begin

    -- REGISTER_CMDADDR:  W   ->  0 - 24  = IOCTL Address
    --                           28 - 25  = Unused
    --                                29  = Write Character to address.
    --                                30  = Execute IOCTL READ
    --                                31  = Execute IOCTL WRITE
    --                           if 30 and 31 are active ('1') execute WRITE then READ.
    -- REGISTER_CMDADDR:  R   ->  0 - 24  = IOCTL Address
    --                                29  = BUSY WITH CHAR WRITE
    --                                30  = DATA AVAILABLE
    --                                31  = BUSY WITH WRITE
    --
    -- REGISTER__DOUT     W   ->  0 - 23  = IOCTL DOUT
    --                                24  = Zoom vertical size character 2x.
    --                                25  = Zoom horizontal size character 2x.
    --                           26 - 27  = Rotation: 00 - Normal, 01 90' Left, 02 90' Right, 11 180'
    --                                28  = Write Menu Character = 1, write Status Character = 0.
    --                                29  = Status char Blue.
    --                                30  = Status char Red.
    --                                31  = Status char Green.
    -- REGISTER_DIN       R   ->  0 - 31  = IOCTL DIN
    -- REGISTER_CHRCOLS   W   ->  0 -  7  = Columns
    -- REGISTER_CHRCOLS   R   ->  0 -  7  = Columns
    -- REGISTER_CGADDR    W   ->  0 - 24  = Start/Base address of CG ROM/RAM.
    -- REGISTER_CGADDR    R   ->  0 - 24  = Start/Base address of CG ROM/RAM.

    -- Input Interface
    process(CLK)
    begin
        if rising_edge(CLK) then

            if (RESET = '1') then
                REGISTER_CMDADDR           <= (others => '0');
                REGISTER_DOUT              <= (others => '0');
                REGISTER_CHRCOLS           <= (others => '0');
                REGISTER_CGADDR            <= (others => '0');

            elsif CLR_WR_CMD = '1' then
                REGISTER_CMDADDR(31)       <= '0';

            elsif CLR_RD_CMD = '1' then
                REGISTER_CMDADDR(30)       <= '0';

            elsif CLR_WR_CHAR_CMD = '1' then
                REGISTER_CMDADDR(29)       <= '0';

            elsif CS = '1' and WREN = '1' then -- valid register write access

                case ADDR is
                    -- Address and Command
                    when  "000" =>
                        REGISTER_CMDADDR   <= DATA_IN;

                    -- Data Out (DOUT)
                    when "001" => 
                        REGISTER_DOUT      <= DATA_IN;

                    -- Character columns per row (CHRCOLS)
                    when "010" => 
                        REGISTER_CHRCOLS   <= DATA_IN(7 downto 0);

                    -- CG ROM/RAM Address (CGADDR)
                    when "011" => 
                        REGISTER_CGADDR    <= DATA_IN(24 downto 0);

                    when others =>

                end case;
            end if;
        end if;    
    end process;

    -- Output Interface
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '1') then
                DATA_OUT                   <= (others => '0');
                CLR_DATA_AVAIL             <= '0';
            else
                if CLR_DATA_AVAIL = '1' then
                    CLR_DATA_AVAIL         <= '0';
                end if;

                --- Data Output ---
                if CS = '1' and RDEN = '1' then -- valid register read request
                    case ADDR is

                        -- Address and Command
                        when "000" =>
                            DATA_OUT       <= WRITE_BUSY & DATA_AVAIL & WRITE_CHAR_BUSY & CON_IOCTL_SELECT & IOCTL_SENSE & "00" & REGISTER_CMDADDR(24 downto 0);

                        -- Data in (DIN)
                        when "001" =>
                            DATA_OUT       <= REGISTER_DIN(31 downto 0);
                            CLR_DATA_AVAIL <= '1';

                        -- Character columns per row (CHRCOLS)
                        when "010" =>
                            DATA_OUT       <= X"000000" & REGISTER_CHRCOLS(7 downto 0);

                        -- Start/Base address of CG ROM/RAM (CGADDR)
                        when "011" =>
                            DATA_OUT       <= "0000000" & REGISTER_CGADDR(24 downto 0);

                        when others =>
                            DATA_OUT       <= (others => '0');
                    end case;
                else
                    DATA_OUT               <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- Process to convert the requested command into an IOCTL transaction.
    --
    process(RESET, CLK)
    begin
        if rising_edge(CLK) then

            if RESET = '1' then
                WRITE_BUSY                             <= '0';
                DATA_AVAIL                             <= '0';
                CLR_RD_CMD                             <= '0';
                CLR_WR_CMD                             <= '0';
                CLR_WR_CHAR_CMD                        <= '0';
                WR_CMD_STATE                           <= 0;
                WR_CHAR_CMD_STATE                      <= 0;
                RD_CMD_STATE                           <= 0;
                CON_IOCTL_WR                           <= '0';
                CON_IOCTL_RD                           <= '0';
                CON_IOCTL_SELECT                       <= '0'; 
                IOCTL_DOWNLOAD                         <= '0'; 
                IOCTL_UPLOAD                           <= '0';
                IOCTL_ADDR                             <= (others => '0'); 
                DST_RAM_ADDR                           <= (others => '0'); 
                DST_CHAR                               <= (others => '0'); 
                DST_HX2                                <= '0';
                DST_VX2                                <= '0';

            else
                if CLR_DATA_AVAIL = '1' then
                    DATA_AVAIL                         <= '0';
                end if;

                -- If the IOCTL bus is inactive or becomes externally active during a transaction, process this modules transaction first, else relinquish control.
                --
                if IOCTL_SENSE = '0' or (IOCTL_SENSE = '1' and CON_IOCTL_SELECT = '1' and (WR_CMD_STATE /= 0 or RD_CMD_STATE /= 0 or WR_CHAR_CMD_STATE /= 0)) then

                    -- Ensure a write transaction can only occur when there is no ongoing read transaction.
                    if REGISTER_CMDADDR(31) = '1' and WR_CMD_STATE = 0 and RD_CMD_STATE = 0 and WR_CHAR_CMD_STATE = 0 then
                        CON_IOCTL_SELECT               <= '1';
                        CLR_WR_CMD                     <= '1';
                        WRITE_BUSY                     <= '1';
                        WR_CMD_STATE                   <= 1;
        
                    -- Ensure that a read transaction can only occur when there is no ongoing write transaction.
                    elsif REGISTER_CMDADDR(31 downto 30) = "01" and RD_CMD_STATE = 0 and WR_CMD_STATE = 0 and WR_CHAR_CMD_STATE = 0 then
                        CON_IOCTL_SELECT               <= '1';
                        CLR_RD_CMD                     <= '1';
                        DATA_AVAIL                     <= '0';
                        RD_CMD_STATE                   <= 1;
       
                    -- Ensure that a write char transaction can only occur when there is no ongoing read/write transaction.
                    elsif REGISTER_CMDADDR(31 downto 29) = "001" and WR_CHAR_CMD_STATE = 0 and WR_CMD_STATE = 0 and RD_CMD_STATE = 0 then
                        CON_IOCTL_SELECT               <= '1';
                        CLR_WR_CHAR_CMD                <= '1';
                        WRITE_CHAR_BUSY                <= '1';
                        WR_CHAR_CMD_STATE              <= 1;
                    end if;

                    -- If we have control of the bus, process.
                    if CON_IOCTL_SELECT = '1' then

                        case WR_CMD_STATE is
                            -- Holding state.
                            when 0 =>
                                CLR_WR_CMD             <= '0';
        
                            when 1 =>
                                IOCTL_ADDR             <= REGISTER_CMDADDR(24 downto 0);
                                IOCTL_DOUT             <= REGISTER_DOUT;
                                IOCTL_DOWNLOAD         <= '1';
                                IOCTL_UPLOAD           <= '0';
                                WR_CMD_STATE           <= 2;
        
                            when 2 =>
                                CON_IOCTL_WR           <= '1';
                                WR_CMD_STATE           <= 3;
        
                            when 3 =>
                                CON_IOCTL_WR           <= '0';
                                WR_CMD_STATE           <= 4;
        
                            when 4 =>
                                WRITE_BUSY             <= '0';
                                IOCTL_DOWNLOAD         <= '0';
                                WR_CMD_STATE           <= 0;
        
                            when others =>
                        end case;
        
                        case RD_CMD_STATE is
                            -- Holding state.
                            when 0 =>
                                CLR_RD_CMD             <= '0';
        
                            when 1 =>
                                IOCTL_ADDR             <= REGISTER_CMDADDR(24 downto 0);
                                IOCTL_UPLOAD           <= '1';
                                IOCTL_DOWNLOAD         <= '0';
                                CON_IOCTL_RD           <= '1';
                                RD_CMD_STATE           <= 2;
        
                            when 2 =>
                                REGISTER_DIN           <= IOCTL_DIN;
                                RD_CMD_STATE           <= 3;

                            when 3 =>
                                CON_IOCTL_RD           <= '0';
                                IOCTL_UPLOAD           <= '0';
                                DATA_AVAIL             <= '1';
                                RD_CMD_STATE           <= 0;

                            when others =>
                        end case;
        
                        case WR_CHAR_CMD_STATE is
                            -- Holding state.
                            when 0 =>
                                CLR_WR_CHAR_CMD        <= '0';
        
                            when 1 =>
                                CG_ROW                 <= (others => '0');
                                WR_CHAR_CMD_STATE      <= 2;
        
                            when 2 =>
                                IOCTL_UPLOAD           <= '1';
                                IOCTL_ADDR             <= std_logic_vector(unsigned(REGISTER_CGADDR(24 downto 0)) + unsigned(REGISTER_DOUT(7 downto 0) & "000") + unsigned(CG_ROW));
                                CON_IOCTL_RD           <= '1';
                                WR_CHAR_CMD_STATE      <= 3;
        
                            when 3 => -- delay to allow valid read from CGROM.
                                WR_CHAR_CMD_STATE      <= 4;

                            when 4 =>
                                for i in 0 to 7 loop
                                    CGCHAR(to_integer(unsigned(CG_ROW)), i)  <= IOCTL_DIN(i);
                                end loop;
                                CON_IOCTL_RD           <= '0';
                                CG_ROW                 <= std_logic_vector(unsigned(CG_ROW) + 1);

                                if CG_ROW = "111" then
                                    IOCTL_UPLOAD       <= '0';
                                    WR_CHAR_CMD_STATE  <= 5;
                                else
                                    WR_CHAR_CMD_STATE  <= 2;
                                end if;
                                    
                            when 5 =>
                                DST_RAM_ADDR           <= REGISTER_CMDADDR(24 downto 0);
                                CG_ROW                 <= (others => '0');
                                IOCTL_DOWNLOAD         <= '1';
                                WR_CHAR_CMD_STATE      <= 6;

                            when 6 =>
                                DST_CHAR               <= X"0000";
                                DST_HX2                <= '1';
                                DST_VX2                <= '1';

                                -- Rotation of character.
                                case REGISTER_DOUT(MODE_ROTATION) is
                                    when "00" => -- Normal
                                        for i in 0 to 7 loop
                                            if REGISTER_DOUT(MODE_H2X) = '0' then
                                                DST_CHAR(i+8)          <= CGCHAR(to_integer(unsigned(CG_ROW)), i);
                                            else
                                                DST_CHAR(i*2)          <= CGCHAR(to_integer(unsigned(CG_ROW)), i);
                                                if REGISTER_DOUT(MODE_HALFPIXEL) = '0' then
                                                    DST_CHAR((i*2)+1)  <= CGCHAR(to_integer(unsigned(CG_ROW)), i);
                                                end if;
                                            end if;
                                        end loop;
                                    when "01" => -- Rotate 90' Left
                                        for i in 7 downto 0 loop
                                            if REGISTER_DOUT(MODE_H2X) = '0' then
                                                DST_CHAR(15-i)         <= CGCHAR(i, to_integer(unsigned(CG_ROW)));
                                            else
                                                DST_CHAR(15-((i*2)+1)) <= CGCHAR(i, to_integer(unsigned(CG_ROW)));
                                                if REGISTER_DOUT(MODE_HALFPIXEL) = '0' then
                                                    DST_CHAR(15-(i*2)) <= CGCHAR(i, to_integer(unsigned(CG_ROW)));
                                                end if;
                                            end if;
                                        end loop;
                                    when "10" => -- Rotate 90' Right
                                        for i in 0 to 7 loop
                                            if REGISTER_DOUT(MODE_H2X) = '0' then
                                                DST_CHAR(i+8)          <= CGCHAR(i, 7-to_integer(unsigned(CG_ROW)));
                                            else
                                                DST_CHAR(i*2)          <= CGCHAR(i, 7-to_integer(unsigned(CG_ROW)));
                                                if REGISTER_DOUT(MODE_HALFPIXEL) = '0' then
                                                    DST_CHAR((i*2)+1)  <= CGCHAR(i, 7-to_integer(unsigned(CG_ROW)));
                                                end if;
                                            end if;
                                        end loop;
                                    when "11" => -- Rotate 180'
                                        for i in 0 to 7 loop
                                            if REGISTER_DOUT(MODE_H2X) = '0' then
                                                DST_CHAR(i+8)          <= CGCHAR(7-to_integer(unsigned(CG_ROW)), i);
                                            else
                                                DST_CHAR(i*2)          <= CGCHAR(7-to_integer(unsigned(CG_ROW)), i);
                                                if REGISTER_DOUT(MODE_HALFPIXEL) = '0' then
                                                    DST_CHAR((i*2)+1)  <= CGCHAR(7-to_integer(unsigned(CG_ROW)), i);
                                                end if;
                                            end if;
                                        end loop;
                                end case;
                                WR_CHAR_CMD_STATE      <= 7;

                            when 7 =>
                                IOCTL_ADDR             <= DST_RAM_ADDR;

                                -- For vertical half pixels, each 2nd row is blank only if we are not skipping horizontal pixels due to horizontal doubling.
                                if REGISTER_DOUT(MODE_HALFPIXEL) = '0' or REGISTER_DOUT(MODE_H2X) = '1' or (REGISTER_DOUT(MODE_HALFPIXEL) = '1' and REGISTER_DOUT(MODE_H2X) = '0' and DST_VX2 = '1') then
                                    for i in 7 downto 0 loop
                                        if REGISTER_DOUT(MODE_FG_GREEN) = '1' and DST_CHAR(i+8) = '1' then
                                            IOCTL_DOUT(i)    <= DST_CHAR(i+8);
                                        elsif REGISTER_DOUT(MODE_BG_GREEN) = '1' and DST_CHAR(i+8) = '0' then
                                            IOCTL_DOUT(i)    <= '1'; --DST_CHAR(i+8);
                                        else
                                            IOCTL_DOUT(i)    <= '0';
                                        end if;

                                        if REGISTER_DOUT(MODE_FG_RED) = '1' and DST_CHAR(i+8) = '1' then
                                            IOCTL_DOUT(i+8)  <= DST_CHAR(i+8);
                                        elsif REGISTER_DOUT(MODE_BG_RED) = '1' and DST_CHAR(i+8) = '0' then
                                            IOCTL_DOUT(i+8)  <= '1'; --DST_CHAR(i+8);
                                        else
                                            IOCTL_DOUT(i+8)  <= '0';
                                        end if;

                                        if REGISTER_DOUT(MODE_FG_BLUE) = '1' and DST_CHAR(i+8) = '1' then
                                            IOCTL_DOUT(i+16) <= DST_CHAR(i+8);
                                        elsif REGISTER_DOUT(MODE_BG_BLUE) = '1' and DST_CHAR(i+8) = '0' then
                                            IOCTL_DOUT(i+16) <= '1'; --DST_CHAR(i+8);
                                        else
                                            IOCTL_DOUT(i+16) <= '0';
                                        end if;
                                    end loop;
                                else
                                    IOCTL_DOUT                  <= X"00000000";
                                end if;
                                WR_CHAR_CMD_STATE      <= 8;

                            when 8 =>
                                CON_IOCTL_WR           <= '1';
                                WR_CHAR_CMD_STATE      <= 9;
        
                            when 9 =>
                                CON_IOCTL_WR           <= '0';
                                if REGISTER_DOUT(MODE_V2X) = '1' and DST_VX2 = '1' then
                                    DST_VX2            <= '0';
                                    DST_RAM_ADDR       <= std_logic_vector(unsigned(DST_RAM_ADDR) + unsigned(REGISTER_CHRCOLS(7 downto 0)));
                                    WR_CHAR_CMD_STATE  <= 7;
                                elsif REGISTER_DOUT(MODE_H2X) = '1' and DST_HX2 = '1' then
                                    if REGISTER_DOUT(MODE_V2X) = '1' then
                                        DST_VX2        <= '1';
                                        DST_RAM_ADDR   <= std_logic_vector(unsigned(DST_RAM_ADDR) - unsigned(REGISTER_CHRCOLS(7 downto 0)) + 1);
                                    else
                                        DST_RAM_ADDR   <= std_logic_vector(unsigned(DST_RAM_ADDR) + 1);
                                    end if;
                                    DST_CHAR(15 downto 8) <= DST_CHAR(7 downto 0);
                                    DST_HX2            <= '0';
                                    WR_CHAR_CMD_STATE  <= 7;
                                elsif CG_ROW = "111" then
                                    WRITE_CHAR_BUSY    <= '0';
                                    IOCTL_DOWNLOAD     <= '0';
                                    WR_CHAR_CMD_STATE  <= 0;
                                else
                                    CG_ROW             <= std_logic_vector(unsigned(CG_ROW) + 1);
                                    if REGISTER_DOUT(MODE_H2X) = '1' then
                                        DST_RAM_ADDR   <= std_logic_vector(unsigned(DST_RAM_ADDR) -1 + unsigned(REGISTER_CHRCOLS(7 downto 0)));
                                    else
                                        DST_RAM_ADDR   <= std_logic_vector(unsigned(DST_RAM_ADDR) + unsigned(REGISTER_CHRCOLS(7 downto 0)));
                                    end if;
                                    WR_CHAR_CMD_STATE  <= 6;
                                end if;

                            when others =>
                        end case;
                    end if;
                else
                    -- Relinquish control of bus.
                    CON_IOCTL_SELECT                   <= '0';
                end if;
            end if;
        end if;
    end process;

    -- IOCTL clock uses system clock.
    --
    IOCTL_CLK            <= CLK; 

    -- Interrupt lines
    --
    IRQ_RD_O             <= '0';
    IRQ_WR_O             <= '0';

    -- Buffers to enable signal state read.
    --
    IOCTL_WR             <= CON_IOCTL_WR;
    IOCTL_RD             <= CON_IOCTL_RD;
    IOCTL_SELECT         <= CON_IOCTL_SELECT;

end Structure;
