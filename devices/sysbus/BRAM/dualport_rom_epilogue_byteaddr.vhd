    others => x"00000000"
);

begin

    process (clk)
    begin
        if (clk'event and clk = '1') then
            if (memAWriteEnable = '1') then
                -- Memory writes are 32bit (default), 16bit or 8 bit.
                --
                if    (memAWriteByte = '1') then
                    ram(to_integer(unsigned(memAAddr(addrbits-1 downto 2))))(((wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 0))))*8) := memAWrite(7 downto 0);
                elsif (memAWriteHalfWord = '1') then
                    ram(to_integer(unsigned(memAAddr(addrbits-1 downto 2))))(((wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 1))))*16) := memAWrite(15 downto 0);
                else
                    ram(to_integer(unsigned(memAAddr(addrbits-1 downto 2)))) := memAWrite;
                end if;
                memARead <= memAWrite;
            else
                -- Memory reads are always 32bit.
                memARead <= ram(to_integer(unsigned(memAAddr(addrbits-1 downto 2))));
            end if;
        end if;
    end process;
    
    process (clk)
    begin
        if (clk'event and clk = '1') then
            -- 2nd port reads and writes are always 32bit.
            if (memBWriteEnable = '1') then
                ram(to_integer(unsigned(memBAddr(addrbits-1 downto 2)))) := memBWrite;
                memBRead <= memBWrite;
            else
                memBRead <= ram(to_integer(unsigned(memBAddr(addrbits-1 downto 2))));
            end if;
        end if;
    end process;
end arch;

