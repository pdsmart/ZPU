library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.zpu_soc_pkg.all;

entity E115_zpu is
    port (
        -- Clock
        CLOCK_25        : in    std_logic;
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

        -- SD Card 1
        SDCARD_MISO     : in    std_logic_vector(SOC_SD_DEVICES-1 downto 0);
        SDCARD_MOSI     : out   std_logic_vector(SOC_SD_DEVICES-1 downto 0);
        SDCARD_CLK      : out   std_logic_vector(SOC_SD_DEVICES-1 downto 0);
        SDCARD_CS       : out   std_logic_vector(SOC_SD_DEVICES-1 downto 0);

        -- UART Serial channels.
        UART_RX_0       : in    std_logic;
        UART_TX_0       : out   std_logic;
        UART_RX_1       : in    std_logic;
        UART_TX_1       : out   std_logic;

        -- DDR2 DRAM
        DDR2_ADDR       : out   std_logic_vector(13 downto 0);              -- 14 bit multiplexed address bus
        DDR2_DQ         : inout std_logic_vector(63 downto 0);              -- 64 bit bidirectional data bus
        DDR2_DQS        : inout std_logic_vector(7 downto 0);               -- 8 bit bidirectional data bus
        DDR2_DQM        : out   std_logic_vector(17 downto 0);               -- eight byte masks
        DDR2_ODT        : out   std_logic_vector(1 downto 0);               -- 14 bit multiplexed address bus
        DDR2_BA         : out   std_logic_vector(2 downto 0);               -- 8 banks 
        DDR2_CS         : out   std_logic_vector(1 downto 0);               -- 2 chip selects.
        DDR2_WE         : out   std_logic;                                  -- write enable
        DDR2_RAS        : out   std_logic;                                  -- row address select
        DDR2_CAS        : out   std_logic;                                  -- columns address select
        DDR2_CKE        : out   std_logic_vector(1 downto 0);               -- 2 clock enable.
        DDR2_CLK        : out   std_logic_vector(1 downto 0)                -- 2 clocks.
    );
END entity;

architecture rtl of E115_zpu is

    signal reset        : std_logic;
    signal sysclk       : std_logic;
    signal memclk       : std_logic;
    signal pll_locked   : std_logic;
    
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
LED <= "00000000";

mypll : entity work.Clock_25to100
port map
(
    inclk0            => CLOCK_25,
    c0                => sysclk,
    c1                => memclk,
    locked            => pll_locked
);

reset<=(not SW(0) xor KEY(0)) and pll_locked;

myVirtualToplevel : entity work.zpu_soc
generic map
(
    SYSCLK_FREQUENCY => SYSCLK_E115_FREQ
)
port map
(    
    SYSCLK            => sysclk,
    MEMCLK            => memclk,
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

    -- SD Card (SPI) signals
    SDCARD_MISO       => SDCARD_MISO,
    SDCARD_MOSI       => SDCARD_MOSI,
    SDCARD_CLK        => SDCARD_CLK,
    SDCARD_CS         => SDCARD_CS,
        
    -- PS/2 signals
    PS2K_CLK_IN       => '1', 
    PS2K_DAT_IN       => '1', 
    PS2K_CLK_OUT      => open, 
    PS2K_DAT_OUT      => open,    
    PS2M_CLK_IN       => '1',    
    PS2M_DAT_IN       => '1',    
    PS2M_CLK_OUT      => open,    
    PS2M_DAT_OUT      => open,    

    -- I²C signals
    I2C_SCL_IO        => open,
    I2C_SDA_IO        => open, 

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
    IOCTL_DIN         => (others => '0'),                  -- Data to be read into HPS.

    -- SDRAM signals which do not exist on the E115
    SDRAM_CLK         => open, --SDRAM_CLK,                -- sdram is accessed at 128MHz
    SDRAM_CKE         => open, --SDRAM_CKE,                -- clock enable.
    SDRAM_DQ          => open, --SDRAM_DQ,                 -- 16 bit bidirectional data bus
    SDRAM_ADDR        => open, --SDRAM_ADDR,               -- 13 bit multiplexed address bus
    SDRAM_DQM         => open, --SDRAM_DQM,                -- two byte masks
    SDRAM_BA          => open, --SDRAM_BA,                 -- two banks
    SDRAM_CS_n        => open, --SDRAM_CS,                 -- a single chip select
    SDRAM_WE_n        => open, --SDRAM_WE,                 -- write enable
    SDRAM_RAS_n       => open, --SDRAM_RAS,                -- row address select
    SDRAM_CAS_n       => open, --SDRAM_CAS,                -- columns address select
    SDRAM_READY       => open,                             -- sd ready.

    -- DDR2 DRAM
    DDR2_ADDR         => DDR2_ADDR,                        -- 14 bit multiplexed address bus
    DDR2_DQ           => DDR2_DQ,                          -- 64 bit bidirectional data bus
    DDR2_DQS          => DDR2_DQS,                         -- 8 bit bidirectional data bus
    DDR2_DQM          => DDR2_DQM,                         -- eight byte masks
    DDR2_ODT          => DDR2_ODT,                         -- 14 bit multiplexed address bus
    DDR2_BA           => DDR2_BA,                          -- 8 banks 
    DDR2_CS           => DDR2_CS,                          -- 2 chip selects.
    DDR2_WE           => DDR2_WE,                          -- write enable
    DDR2_RAS          => DDR2_RAS,                         -- row address select
    DDR2_CAS          => DDR2_CAS,                         -- columns address select
    DDR2_CKE          => DDR2_CKE,                         -- 2 clock enable.
    DDR2_CLK          => DDR2_CLK                          -- 2 clocks.
);


end architecture;
