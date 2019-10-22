---------------------------------------------------------------------------------------------------------
--
-- Name:            dpram.vhd
-- Created:         January 2019
-- Author(s):       Altera/Intel - refactored by Philip Smart for the ZPU Evo
-- Description:     Dual Port RAM as provided by Altera in the Megafunctions suite.
--
-- Credits:         
-- Copyright:       (c) Altera/Intel
--
-- History:         January 2019   - Initial module taken and refactored, customizing for the ZPU Evo.
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

LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.all;

ENTITY dpram IS
    GENERIC
    (
        init_file                        : string                                         := "";
        widthad_a                        : natural;
        width_a                          : natural                                        := 8;
        widthad_b                        : natural;
        width_b                          : natural                                        := 8;
--      clock_en_a                       : string                                         := "NORMAL";
--      clock_en_b                       : string                                         := "NORMAL";
        outdata_reg_a                    : string                                         := "UNREGISTERED";
        outdata_reg_b                    : string                                         := "UNREGISTERED"
    );
    PORT
    (
        clock_a                          : IN STD_LOGIC;
        clocken_a                        : IN STD_LOGIC                                   := '1';
        address_a                        : IN STD_LOGIC_VECTOR (widthad_a-1 DOWNTO 0);
        data_a                           : IN STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
        wren_a                           : IN STD_LOGIC                                   := '1';
        q_a                              : OUT STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);

        clock_b                          : IN STD_LOGIC;
        clocken_b                        : IN STD_LOGIC                                   := '1';
        address_b                        : IN STD_LOGIC_VECTOR (widthad_b-1 DOWNTO 0);
        data_b                           : IN STD_LOGIC_VECTOR (width_b-1 DOWNTO 0);
        wren_b                           : IN STD_LOGIC                                   := '1';
        q_b                              : OUT STD_LOGIC_VECTOR (width_b-1 DOWNTO 0)
    );
END dpram;


ARCHITECTURE SYN OF dpram IS

    SIGNAL sub_wire0                     : STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
    SIGNAL sub_wire1                     : STD_LOGIC_VECTOR (width_b-1 DOWNTO 0);

    COMPONENT altsyncram
    GENERIC (
        address_reg_b                    : STRING;
        clock_enable_input_a             : STRING;
        clock_enable_input_b             : STRING;
        clock_enable_output_a            : STRING;
        clock_enable_output_b            : STRING;
        indata_reg_b                     : STRING;
        init_file                        : STRING;
        intended_device_family           : STRING;
        lpm_type                         : STRING;
        numwords_a                       : NATURAL;
        numwords_b                       : NATURAL;
        operation_mode                   : STRING;
        outdata_aclr_a                   : STRING;
        outdata_aclr_b                   : STRING;
        outdata_reg_a                    : STRING;
        outdata_reg_b                    : STRING;
        power_up_uninitialized           : STRING;
        read_during_write_mode_port_a    : STRING;
        read_during_write_mode_port_b    : STRING;
        widthad_a                        : NATURAL;
        widthad_b                        : NATURAL;
        width_a                          : NATURAL;
        width_b                          : NATURAL;
        width_byteena_a                  : NATURAL;
        width_byteena_b                  : NATURAL;
        wrcontrol_wraddress_reg_b        : STRING
    );
    PORT (
            clock0                       : IN  STD_LOGIC ;
            clocken0                     : IN  STD_LOGIC ;
            address_a                    : IN  STD_LOGIC_VECTOR (widthad_a-1 DOWNTO 0);
            data_a                       : IN  STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
            wren_a                       : IN  STD_LOGIC ;
            q_a                          : OUT STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);

            clock1                       : IN  STD_LOGIC ;
            clocken1                     : IN  STD_LOGIC ;
            address_b                    : IN  STD_LOGIC_VECTOR (widthad_b-1 DOWNTO 0);
            data_b                       : IN  STD_LOGIC_VECTOR (width_b-1 DOWNTO 0);
            wren_b                       : IN  STD_LOGIC ;
            q_b                          : OUT STD_LOGIC_VECTOR (width_b-1 DOWNTO 0)
    );
    END COMPONENT;

BEGIN
    q_a    <= sub_wire0(width_a-1 DOWNTO 0);
    q_b    <= sub_wire1(width_b-1 DOWNTO 0);

    altsyncram_component : altsyncram
    GENERIC MAP (
        address_reg_b                    => "CLOCK1",
        clock_enable_input_a             => "NORMAL",
        clock_enable_input_b             => "NORMAL",
        clock_enable_output_a            => "BYPASS",
        clock_enable_output_b            => "BYPASS",
        indata_reg_b                     => "CLOCK1",
        init_file                        => init_file,
        intended_device_family           => "Cyclone V",
        lpm_type                         => "altsyncram",
        numwords_a                       => 2**widthad_a,
        numwords_b                       => 2**widthad_b,
        operation_mode                   => "BIDIR_DUAL_PORT",
      --operation_mode                   => "ROM",
        outdata_aclr_a                   => "NONE",
        outdata_aclr_b                   => "NONE",
        outdata_reg_a                    => outdata_reg_a,
        outdata_reg_b                    => outdata_reg_b,
        power_up_uninitialized           => "FALSE",
        read_during_write_mode_port_a    => "NEW_DATA_NO_NBE_READ",
        read_during_write_mode_port_b    => "NEW_DATA_NO_NBE_READ",
        widthad_a                        => widthad_a,
        widthad_b                        => widthad_b,
        width_a                          => width_a,
        width_b                          => width_b,
        width_byteena_a                  => 1,
        width_byteena_b                  => 1,
        wrcontrol_wraddress_reg_b        => "CLOCK1"
    )
    PORT MAP (
        clock0                           => clock_a,
        clocken0                         => clocken_a,
        address_a                        => address_a,
        data_a                           => data_a,
        wren_a                           => wren_a,
        q_a                              => sub_wire0,

        clock1                           => clock_b,
        clocken1                         => clocken_b,
        address_b                        => address_b,
        wren_b                           => wren_b,
        data_b                           => data_b,
        q_b                              => sub_wire1
    );



END SYN;
