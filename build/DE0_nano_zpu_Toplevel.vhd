library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.zpu_soc_pkg.all;

entity DE0_nano_zpu is
    port (
        -- Clock
        CLOCK_50        : in    std_logic;
        -- LED
        LED             : out   std_logic_vector(7 downto 0);
        -- Debounced keys
        KEY             : in    std_logic_vector(1 downto 0);
        -- DIP switches
        SW              : in    std_logic_vector(3 downto 0);
    
    --  TDI             : in    std_logic;
    --  TCK             : in    std_logic;
    --  TCS             : in    std_logic;
    --  TDO             : out   std_logic;
    --  I2C_SDAT        : inout std_logic;
    --  I2C_SCLK        : out   std_logic;
    --  GPIO_0          : inout std_logic_vector(33 downto 0);
    --  GPIO_1          : inout std_logic_vector(33 downto 0);
    
        UART_RX_0       : in    std_logic;
        UART_TX_0       : out   std_logic;
        UART_RX_1       : in    std_logic;
        UART_TX_1       : out   std_logic
    
    );
END entity;

architecture rtl of DE0_nano_zpu is

    signal reset : std_logic;
    signal sysclk : std_logic;
    signal pll_locked : std_logic;
    
    --signal ps2m_clk_in : std_logic;
    --signal ps2m_clk_out : std_logic;
    --signal ps2m_dat_in : std_logic;
    --signal ps2m_dat_out : std_logic;
    
    --signal ps2k_clk_in : std_logic;
    --signal ps2k_clk_out : std_logic;
    --signal ps2k_dat_in : std_logic;
    --signal ps2k_dat_out : std_logic;
    
    --alias PS2_MDAT : std_logic is GPIO_1(19);
    --alias PS2_MCLK : std_logic is GPIO_1(18);

begin

--I2C_SDAT    <= 'Z';
--GPIO_0(33 downto 2) <= (others => 'Z');
--GPIO_1 <= (others => 'Z');
--LED <= "101010" & reset & UART_RX_0;

mypll : entity work.Clock_50to100
port map
(
    inclk0 => CLOCK_50,
    c0 => sysclk,
    c1 => open, --DRAM_CLK,
    locked => pll_locked
);

reset<=(not SW(0) xor KEY(0)) and pll_locked;

myVirtualToplevel : entity work.zpu_soc
generic map
(
    sysclk_frequency => SYSCLK_FREQUENCY
)
port map
(    
    SYSCLK            => sysclk,
    RESET_IN          => reset,

    -- RS232
    UART_RX_0         => UART_RX_0,
    UART_TX_0         => UART_TX_0,
    UART_RX_1         => UART_RX_1,
    UART_TX_1         => UART_TX_1,

    -- SPI signals
    SPI_MISO          => '1',                              -- Allow the SPI interface not to be plumbed in.
    SPI_MOSI          => open,    
    SPI_CLK           => open,    
    SPI_CS            => open,    
        
    -- PS/2 signals
    PS2K_CLK_IN       => '1', 
    PS2K_DAT_IN       => '1', 
    PS2K_CLK_OUT      => open, 
    PS2K_DAT_OUT      => open,    
    PS2M_CLK_IN       => '1',    
    PS2M_DAT_IN       => '1',    
    PS2M_CLK_OUT      => open,    
    PS2M_DAT_OUT      => open,    

LED             => LED,

    -- IOCTL Bus --
    IOCTL_DOWNLOAD    => open,                             -- Downloading to FPGA.
    IOCTL_UPLOAD      => open,                             -- Uploading from FPGA.
    IOCTL_CLK         => open,                             -- I/O Clock.
    IOCTL_WR          => open,                             -- Write Enable to FPGA.
    IOCTL_RD          => open,                             -- Read Enable from FPGA.
    IOCTL_SENSE       => '0',                              -- Sense to see if HPS accessing ioctl bus.
    IOCTL_SELECT      => open,                             -- Enable IOP control over ioctl bus.
    IOCTL_ADDR        => open,                             -- Address in FPGA to write into.
    IOCTL_DOUT        => open,                             -- Data to be written into FPGA.
    IOCTL_DIN         => (others => '0')                   -- Data to be read into HPS.
);


end architecture;
