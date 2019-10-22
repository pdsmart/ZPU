    others => x"00000000"
);

begin

process (clk)
begin
    if (clk'event and clk = '1') then
        if (memAWriteEnable = '1') and (memBWriteEnable = '1') and (memAAddr=memBAddr) and (memAWrite/=memBWrite) then
            report "write collision" severity failure;
        end if;
    
        -- Memory writes are 32bit (default), 16bit or 8 bit.
        --
        if (memAWriteEnable = '1') then
            if    (memAWriteByte = '1') then
                ram(to_integer(unsigned(memAAddr(ADDR_BIT_BRAM_32BIT_RANGE))))(((wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 0))))*8+7) downto (wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 0))))*8) := memAWrite(7 downto 0);
            elsif (memAWriteWord = '1') then
                ram(to_integer(unsigned(memAAddr(ADDR_BIT_BRAM_32BIT_RANGE))))(((wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 1))))*16+15) downto (wordBytes-1-to_integer(unsigned(memAAddr(byteBits-1 downto 1))))*16) := memAWrite(15 downto 0);
            else
                ram(to_integer(unsigned(memAAddr(ADDR_BIT_BRAM_32BIT_RANGE)))) := memAWrite;
            end if;
            memARead <= memAWrite;
        else
            memARead <= ram(to_integer(unsigned(memAAddr(ADDR_BIT_BRAM_32BIT_RANGE))));
        end if;
    end if;
end process;

process (clk)
begin
    if (clk'event and clk = '1') then
        if (memBWriteEnable = '1') then
            ram(to_integer(unsigned(memBAddr(ADDR_BIT_BRAM_32BIT_RANGE)))) := memBWrite;
            memBRead <= memBWrite;
        else
            memBRead <= ram(to_integer(unsigned(memBAddr(ADDR_BIT_BRAM_32BIT_RANGE))));
        end if;
    end if;
end process;


end arch;

