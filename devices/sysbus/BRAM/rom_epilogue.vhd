        others => x"00000000"
    );

begin

process (clk)
begin
    if (clk'event and clk = '1') then
        if (memAWriteEnable = '1') and (memBWriteEnable = '1') and (memAAddr=memBAddr) and (memAWrite/=memBWrite) then
            report "write collision" severity failure;
        end if;
    
        if (memAWriteEnable = '1') then
            ram(to_integer(unsigned(memAAddr(ADDR_32BIT_BRAM_RANGE)))) := memAWrite;
            memARead <= memAWrite;
        else
            memARead <= ram(to_integer(unsigned(memAAddr(ADDR_32BIT_BRAM_RANGE))));
        end if;
    end if;
end process;

process (clk)
begin
    if (clk'event and clk = '1') then
        if (memBWriteEnable = '1') then
            ram(to_integer(unsigned(memBAddr(ADDR_32BIT_BRAM_RANGE)))) := memBWrite;
            memBRead <= memBWrite;
        else
            memBRead <= ram(to_integer(unsigned(memBAddr(ADDR_32BIT_BRAM_RANGE))));
        end if;
    end if;
end process;


end arch;

