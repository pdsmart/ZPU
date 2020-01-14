-- ZPU
--
-- Copyright 2004-2008 oharboe - �yvind Harboe - oyvind.harboe@zylin.com
-- Modified by Philip Smart 02/2019 for the ZPU Evo implementation.
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

entity dualportram is
port (
        clk                  : in  std_logic;
        areset               : in  std_logic := '0';
        memAWriteEnable      : in  std_logic;
        memAAddr             : in  std_logic_vector(ADDR_32BIT_BRAM_RANGE);
        memAWrite            : in  std_logic_vector(WORD_32BIT_RANGE);
        memBWriteEnable      : in  std_logic;
        memBAddr             : in  std_logic_vector(ADDR_32BIT_BRAM_RANGE);
        memBWrite            : in  std_logic_vector(WORD_32BIT_RANGE);
        memARead             : out std_logic_vector(WORD_32BIT_RANGE);
        memBRead             : out std_logic_vector(WORD_32BIT_RANGE)
);
end dualportram;

architecture arch of dualportram is

type ram_type is array(natural range 0 to (2**(SOC_MAX_ADDR_BRAM_BIT-2))-1) of std_logic_vector(WORD_32BIT_RANGE);

shared variable ram : ram_type :=
(
