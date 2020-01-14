////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            zpu_soc.h
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPU System On a Chip utilities.
//                  A set of utilities specific to interaction with the ZPU SoC hardware.
//
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         January 2019   - Initial script written.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////
// This source file is free software: you can redistribute it and#or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
/////////////////////////////////////////////////////////////////////////////////////////////////////////
#ifndef __ZPUSOC_H__
#define __ZPUSOC_H__

#ifndef ASSEMBLY
typedef volatile unsigned int* register_t;
#endif

// Macro to omit code if deemed optional and the compile time flag MINIMUM_FUNCTIONALITY is defined.
#ifdef MINIMUM_FUNCTIONALITY
#define OPTIONAL(a) 
#else
#define OPTIONAL(a)  a
#endif

// System settings.
#define CLK_FREQ                       100000000UL                  // Default frequency used to configure SoC if not present.

// Memory sizes and devices implemented - these can be ignored if the SoC Configuration register is implemented as this provides the exact build configuration.
#define ZPU_ID                         0x0000
#define WB_IMPL                        0
#define WB_SDRAM_IMPL                  0
#define WB_I2C_IMPL                    0
#define BRAM_IMPL                      1
#define RAM_IMPL                       1
#define INSN_BRAM_IMPL                 1
#define SDRAM_IMPL                     1
#define IOCTL_IMPL                     1
#define PS2_IMPL                       1
#define SPI_IMPL                       1
#define SD_IMPL                        1
#define SD_DEVICE_CNT                  1
#define INTRCTL_IMPL                   1
#define INTRCTL_CHANNELS               16
#define TIMER1_IMPL                    1
#define TIMER1_TIMERS_CNT              1
#define SDRAM_ADDR                     0x00010000
#define SDRAM_SIZE                     0x00810000
#define WB_SDRAM_ADDR                  0x01000000
#define WB_SDRAM_SIZE                  0x017FFFFF
#define BRAM_ADDR                      0x00000000
#define BRAM_SIZE                      0x00007FFF
#define INSN_BRAM_ADDR                 0x00000000
#define INSN_BRAM_SIZE                 0x00007FFF
#define RAM_ADDR                       0x00010000
#define RAM_SIZE                       0x00007FFF
#define STACK_BRAM_ADDR                0x00007800
#define STACK_BRAM_SIZE                0x000007FF
#define CPU_RESET_ADDR                 0x00000000
#define CPU_MEM_START                  0x00000000
#define BRAM_APP_START_ADDR            0x2000

//
#define SPIISBLOCKING                  1
#define BIT(x)                         (1<<(x))
#define MEMIO32                        *(volatile unsigned int *)

// ZPU Id definitions.
//
#define ZPU_ID_SMALL                   0x01
#define ZPU_ID_MEDIUM                  0x02
#define ZPU_ID_FLEX                    0x03
#define ZPU_ID_EVO                     0x04
#define ZPU_ID_EVO_MINIMAL             0x05

// IO base address.
//#define IO_ADDR_PERIPHERALS            0xFFFFF000
#define IO_ADDR_PERIPHERALS            0x0F00000
#define IO_ADDR_WB_PERIPHERALS         0x1F00000

// Baud rate computation for UART
#define BAUDRATEGEN(b,x,y)             (((UART_SYSCLK(b)/(x))) << 16) | (((UART_SYSCLK(b)/(y))))

// ----------------------------------
// CPU Bus I/O Peripheral definition.
// ----------------------------------

// IO Processor Controller.
#define IOCTL_BASE                     IO_ADDR_PERIPHERALS + 0x800
#define CMDADDR_REGISTER               0x00
#define DATA_REGISTER                  0x04
#define CHRCOLS_REGISTER               0x08
#define CGADDR_REGISTER                0x0C
#define IOCTL_CMDADDR                  (MEMIO32 (IOCTL_BASE + CMDADDR_REGISTER))
#define IOCTL_DOUT                     (MEMIO32 (IOCTL_BASE + DATA_REGISTER))
#define IOCTL_DIN                      (MEMIO32 (IOCTL_BASE + DATA_REGISTER))
#define IOCTL_CHRCOLS                  (MEMIO32 (IOCTL_BASE + CHRCOLS_REGISTER))
#define IOCTL_CGADDR                   (MEMIO32 (IOCTL_BASE + CGADDR_REGISTER))

// SD Card Controller.
#define SD_BASE                        IO_ADDR_PERIPHERALS + 0x900
#define SD0                            0
#define SD1                            1
#define SD2                            2
#define SD3                            3
#define SD_SPACING                     0x10
#define SD_ADDR_REGISTER               0x00
#define SD_DATA_REGISTER               0x04
#define SD_STATUS_REGISTER             0x0c
#define SD_CMD_REGISTER                0x0c
#define SD_CMD_RESET                   0x00000001
#define SD_CMD_WRITE                   0x00000002
#define SD_CMD_READ                    0x00000004
#define SD_CMD_CARDTYPE                0x00000008
#define SD_CMD_CARDTYPE_SD             0x00000008
#define SD_CMD_CARDTYPE_SDHC           0x00000088
#define SD_STATUS_CONTINUE             0x00000001
#define SD_STATUS_BUSY                 0x00000002
#define SD_STATUS_HNDSHK_OUT           0x00000004
#define SD_STATUS_HNDSHK_IN            0x00000008
#define SD_STATUS_DATA_REQ             0x00000010
#define SD_STATUS_DATA_VALID           0x00000020
#define SD_STATUS_OVERRUN              0x00000040
#define SD_STATUS_IDLESTATE            0x00010000
#define SD_STATUS_ERASERESET           0x00020000
#define SD_STATUS_ILLEGALCMD           0x00040000
#define SD_STATUS_CRCERROR             0x00080000
#define SD_STATUS_ERASESEQ             0x00100000
#define SD_STATUS_ADDRERR              0x00200000
#define SD_STATUS_PARAMERR             0x00400000
#define SD_STATUS_ERROR                0xFFFF0000
#define SD(x, y)                       (MEMIO32 (SD_BASE+(x*SD_SPACING) + y))
#define SD_ADDR(x)                     (MEMIO32 (SD_BASE+(x*SD_SPACING) + SD_ADDR_REGISTER)) 
#define SD_DATA(x)                     (MEMIO32 (SD_BASE+(x*SD_SPACING) + SD_DATA_REGISTER))
#define SD_CMD(x)                      (MEMIO32 (SD_BASE+(x*SD_SPACING) + SD_CMD_REGISTER))
#define SD_STATUS(x)                   (MEMIO32 (SD_BASE+(x*SD_SPACING) + SD_STATUS_REGISTER))
#define IS_SD_BUSY(x)                  ((MEMIO32 (SD_BASE+(x*SD_SPACING) + SD_STATUS_REGISTER)) & SD_STATUS_BUSY) >> 1
#define IS_SD_ERROR(x)                 ((MEMIO32 (SD_BASE+(x*SD_SPACING) + SD_STATUS_REGISTER)) & SD_STATUS_ERROR) >> 16

// UART definitions.
#define UART_BASE                      IO_ADDR_PERIPHERALS + 0xA00
#define UART0                          0
#define UART1                          1
#define UART_SPACING                   0x10           // Address spacing between UART modules.
// UART Registers and macros to read/write them.
#define UART_DATA_REGISTER             0x00
#define UART_CTRL_REGISTER             0x04
#define UART_STATUS_REGISTER           0x04
#define UART_FIFO_REGISTER             0x08
#define UART_BAUDRATE_REGISTER         0x0C
#define UART_SYSCLK_REGISTER           0x0C
#define UART_DATA(x)                   (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_DATA_REGISTER))
#define UART_STATUS(x)                 (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_STATUS_REGISTER))
#define UART_FIFO_STATUS(x)            (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_FIFO_REGISTER))
#define UART_CTRL(x)                   (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_CTRL_REGISTER))
#define UART_BRGEN(x)                  (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_BAUDRATE_REGISTER))
#define UART_SYSCLK(x)                 (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_SYSCLK_REGISTER))
// UART Status flags.
#define UART_RX_FIFO_EMPTY             0x00000001
#define UART_RX_FIFO_FULL              0x00000002
#define UART_RX_DATA_READY             0x00000004
#define UART_RX_OVERRUN                0x00000008
#define UART_RX_INTERRUPT              0x00000010
#define UART_RX_FIFO_ENABLED           0x00000020
#define UART_RX_ENABLED                0x00000040
#define UART_RX_IN_RESET               0x00000080
#define UART_TX_FIFO_EMPTY             0x00010000
#define UART_TX_FIFO_FULL              0x00020000
#define UART_TX_BUSY                   0x00040000
#define UART_TX_DATA_LOADED            0x00080000
#define UART_TX_OVERRUN                0x00100000
#define UART_TX_INTERRUPT              0x00200000
#define UART_TX_FIFO_ENABLED           0x00400000
#define UART_TX_ENABLED                0x00800000
#define UART_TX_IN_RESET               0x01000000
// UART Control flags.
#define UART_RX_ENABLE                 0x00000001
#define UART_RX_FIFO_ENABLE            0x00000002
#define UART_RX_RESET                  0x00000004
#define UART_TX_ENABLE                 0x00010000
#define UART_TX_FIFO_ENABLE            0x00020000
#define UART_TX_RESET                  0x00040000
// UART macros to test 32bit status register value.
#define UART_IS_TX_FIFO_ENABLED(x)     ((x & UART_TX_FIFO_ENABLED) != 0)
#define UART_IS_TX_FIFO_DISABLED(x)    ((x & UART_TX_FIFO_ENABLED) == 0)
#define UART_IS_TX_FIFO_FULL(x)        ((x & UART_TX_FIFO_FULL) != 0)
#define UART_IS_TX_BUSY(x)             ((x & UART_TX_BUSY) != 0)
#define UART_IS_TX_DATA_LOADED(x)      ((x & UART_TX_DATA_LOADED) != 0)
#define UART_IS_RX_FIFO_ENABLED(x)     ((x & UART_RX_FIFO_ENABLED) != 0)
#define UART_IS_RX_FIFO_DISABLED(x)    ((x & UART_RX_FIFO_ENABLED) == 0)
#define UART_IS_RX_FIFO_EMPTY(x)       ((x & UART_RX_FIFO_EMPTY) != 0)
#define UART_IS_RX_DATA_READY(x)       ((x & UART_RX_DATA_READY) != 0)
// UART macros to test for a specific flag.
#define UART_STATUS_RX_FIFO_EMPTY(x)   (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_FIFO_EMPTY
#define UART_STATUS_RX_FIFO_FULL(x)    (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_FIFO_FULL
#define UART_STATUS_RX_DATA_READY(x)   (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_DATA_READY
#define UART_STATUS_RX_OVERRUN(x)      (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_OVERRUN
#define UART_STATUS_RX_INTR(x)         (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_INTERRUPT
#define UART_STATUS_RX_FIFO_ENABLED(x) (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_FIFO_ENABLED
#define UART_STATUS_RX_ENABLED(x)      (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_RX_ENABLED
#define UART_STATUS_RX_IN_RESET(x)     (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_RX_REGISTER)) & UART_IN_RESET
#define UART_STATUS_TX_FIFO_EMPTY(x)   (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_FIFO_EMPTY
#define UART_STATUS_TX_FIFO_FULL(x)    (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_FIFO_FULL
#define UART_STATUS_TX_BUSY(x)         (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_BUSY
#define UART_STATUS_TX_DATA_LOADED(x)  (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_DATA_LOADED
#define UART_STATUS_TX_OVERRUN(x)      (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_OVERRUN
#define UART_STATUS_TX_INTR(x)         (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_INTERRUPT
#define UART_STATUS_TX_FIFO_ENABLED(x) (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_FIFO_ENABLED
#define UART_STATUS_TX_ENABLED(x)      (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_TX_ENABLED
#define UART_STATUS_TX_IN_RESET(x)     (MEMIO32 (UART_BASE+(x*UART_SPACING)+UART_TX_REGISTER)) & UART_IN_RESET

// Interrupt Controller.
#define INTERRUPT_BASE                 IO_ADDR_PERIPHERALS + 0xB00
#define INTR0                          0
#define INTERRUPT_SPACING              0x10
#define INTERRUPT_STATUS_REGISTER      0x0
#define INTERRUPT_CTRL_REGISTER        0x4
#define INTERRUPT(x,y)                 (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING)+y))
#define INTERRUPT_STATUS(x)            (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING)+INTERRUPT_STATUS_REGISTER))
#define INTERRUPT_CTRL(x)              (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING)+INTERRUPT_CTRL_REGISTER))
// Interrupt bit locations.
#define INTR_TIMER                     0x00000002
#define INTR_PS2                       0x00000004
#define INTR_IOCTL_RD                  0x00000008
#define INTR_IOCTL_WR                  0x00000010
#define INTR_UART0_RX                  0x00000020
#define INTR_UART0_TX                  0x00000040
#define INTR_UART1_RX                  0x00000080
#define INTR_UART1_TX                  0x00000100
// Macros to test a specific interrupt, ignoring others.
#define INTR_TEST_TIMER(x)             (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_TIMER
#define INTR_TEST_PS2(x)               (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_PS2
#define INTR_TEST_IOCTL_RD(x)          (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_IOCTL_RD
#define INTR_TEST_IOCTL_WR(x)          (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_IOCTL_WR
#define INTR_TEST_UART0_RX(x)          (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_UART0_RX
#define INTR_TEST_UART0_TX(x)          (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_UART0_TX
#define INTR_TEST_UART1_RX(x)          (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_UART1_RX
#define INTR_TEST_UART1_TX(x)          (MEMIO32 (INTERRUPT_BASE+(x*INTERRUPT_SPACING))) & INTR_UART1_TX
// Macros to test a variable for a specific interrupt.
#define INTR_IS_TIMER(x)               (x) & INTR_TIMER
#define INTR_IS_PS2(x)                 (x) & INTR_PS2
#define INTR_IS_IOCTL_RD(x)            (x) & INTR_IOCTL_RD
#define INTR_IS_IOCTL_WR(x)            (x) & INTR_IOCTL_WR
#define INTR_IS_UART0_RX(x)            (x) & INTR_UART0_RX
#define INTR_IS_UART0_TX(x)            (x) & INTR_UART0_TX
#define INTR_IS_UART1_RX(x)            (x) & INTR_UART1_RX
#define INTR_IS_UART1_TX(x)            (x) & INTR_UART1_TX

// Timer.
// TIMER0 -> An RTC down to microsecond resolution and 3 delay counters, 1x uS and 1x mS down counters and 1x mS up counter.
// TIMER1-> are standard timers.
#define TIMER_BASE                     IO_ADDR_PERIPHERALS + 0xC00
#define TIMER_SPACING                  0x40
#define TIMER0                         0
#define TIMER1                         1
#define TIMER_ENABLE_REG               0x00
#define TIMER_INDEX_REG                0x04
#define TIMER_COUNTER_REG              0x08
#define TIMER_MICROSEC_DOWN_REG        0x00
#define TIMER_MILLISEC_DOWN_REG        0x04
#define TIMER_MILLISEC_UP_REG          0x08
#define TIMER_SECONDS_DOWN_REG         0x0C
#define RTC_CTRL_HALT                  0x00000001
#define RTC_CONTROL_REG                0x1C
#define RTC_MICROSECONDS_REG           0x20
#define RTC_MILLISECONDS_REG           0x24
#define RTC_SECOND_REG                 0x28
#define RTC_MINUTE_REG                 0x2C
#define RTC_HOUR_REG                   0x30
#define RTC_DAY_REG                    0x34
#define RTC_MONTH_REG                  0x38
#define RTC_YEAR_REG                   0x3C
#define TIMER(x, y)                    (MEMIO32 (TIMER_BASE+(x*TIMER_SPACING) + y))
#define TIMER_ENABLE(x)                (MEMIO32 (TIMER_BASE+(x*TIMER_SPACING) + TIMER_ENABLE_REG))
#define TIMER_INDEX(x)                 (MEMIO32 (TIMER_BASE+(x*TIMER_SPACING) + TIMER_INDEX_REG))
#define TIMER_COUNTER(x)               (MEMIO32 (TIMER_BASE+(x*TIMER_SPACING) + TIMER_COUNTER_REG))
#define TIMER_MICROSECONDS_DOWN        (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + TIMER_MICROSEC_DOWN_REG))
#define TIMER_MILLISECONDS_DOWN        (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + TIMER_MILLISEC_DOWN_REG))
#define TIMER_MILLISECONDS_UP          (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + TIMER_MILLISEC_UP_REG))
#define TIMER_SECONDS_DOWN             (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + TIMER_SECONDS_DOWN_REG))
#define RTC_CONTROL                    (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_CONTROL_REG))
#define RTC_MICROSECONDS               (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_MICROSECONDS_REG))
#define RTC_MILLISECONDS               (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_MILLISECONDS_REG))
#define RTC_SECOND                     (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_SECOND_REG))
#define RTC_MINUTE                     (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_MINUTE_REG))
#define RTC_HOUR                       (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_HOUR_REG))
#define RTC_DAY                        (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_DAY_REG))
#define RTC_MONTH                      (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_MONTH_REG))
#define RTC_YEAR                       (MEMIO32 (TIMER_BASE+(TIMER0*TIMER_SPACING) + RTC_YEAR_REG))

// SPI Controller.
#define SPI_BASE                       IO_ADDR_PERIPHERALS + 0xD00
#define SPI0                           0
#define SPI1                           1
#define SPI2                           2
#define SPI3                           3
#define SPI_SPACING                    0x10
#define CS_REGISTER                    0x00
#define DATA_REGISTER                  0x04
#define PUMP_REGISTER                  0x08
#define SPI(x, y)                      (MEMIO32 (SPI_BASE+(x*SPI_SPACING) + y))
#define SPI_CS(x)                      (MEMIO32 (SPI_BASE+(x*SPI_SPACING) + CS_REGISTER))     /* CS bits are write-only, but bit 15 reads as the SPI busy signal */
#define SPI_DATA(x)                    (MEMIO32 (SPI_BASE+(x*SPI_SPACING) + DATA_REGISTER))   /* Blocks on both reads and writes, making BUSY signal redundant. */
#define SPI_PUMP(x)                    (MEMIO32 (SPI_BASE+(x*SPI_SPACING) + PUMP_REGISTER))   /* Push 16-bits through SPI in one instruction */
#define SPI_SET_CS(x,y)                {while((SPI_CS(x)&(1<<SPI_BUSY))); SPI_CS(x)=(y);}
#define SPI_CS_SD                      0
#define SPI_FAST                       8
#define SPI_BUSY                       15

// PS2
#define PS2_BASE                       IO_ADDR_PERIPHERALS + 0xE00
#define PS2_0                          0
#define PS2_1                          1
#define PS2_SPACING                    0x10
#define PS2_KEYBOARD_REGISTER          0
#define PS2_MOUSE_REGISTER             0x4
#define PS2(x, y)                      (MEMIO32 (PS2_BASE+(x*0x10) + y))
#define PS2_KEYBOARD(x)                (MEMIO32 (PS2_BASE+(x*0x10) + PS2_KEYBOARD_REGISTER))
#define PS2_MOUSE(x)                   (MEMIO32 (PS2_BASE+(x*0x10) + PS2_MOUSE_REGISTER))
#define BIT_PS2_RECV                   11
#define BIT_PS2_CTS                    10

// SoC Configuration registers.
#define SOCCFG_BASE                    IO_ADDR_PERIPHERALS + 0xF00
// Registers
#define SOCCFG_ZPU_ID                  0x00                                                   // ID of the instantiated ZPU
#define SOCCFG_SYSFREQ                 0x04                                                   // System Clock Frequency in MHz x 10 (ie. 100KHź)
#define SOCCFG_MEMFREQ                 0x08                                                   // Sysbus SDRAM Clock Frequency in MHz x 10 (ie. 100KHź)
#define SOCCFG_WBMEMFREQ               0x0c                                                   // Wishbone SDRAM Clock Frequency in MHz x 10 (ie. 100KHź)
#define SOCCFG_DEVIMPL                 0x10                                                   // Bit map of devices implemented in SOC.
#define SOCCFG_BRAMADDR                0x14                                                   // Address of Block RAM.
#define SOCCFG_BRAMSIZE                0x18                                                   // Size of Block RAM.
#define SOCCFG_RAMADDR                 0x1c                                                   // Address of RAM (additional BRAM, DRAM etc).
#define SOCCFG_RAMSIZE                 0x20                                                   // Size of RAM.
#define SOCCFG_BRAMINSNADDR            0x24                                                   // Address of dedicated instruction Block RAM.
#define SOCCFG_BRAMINSNSIZE            0x28                                                   // Size of dedicated instruction Block RAM.
#define SOCCFG_SDRAMADDR               0x2c                                                   // Address of SDRAM.
#define SOCCFG_SDRAMSIZE               0x30                                                   // Size of SDRAM.
#define SOCCFG_WBSDRAMADDR             0x34                                                   // Address of Wishbone SDRAM.
#define SOCCFG_WBSDRAMSIZE             0x38                                                   // Size of Wishbone SDRAM.
#define SOCCFG_CPURSTADDR              0x3c                                                   // Address CPU executes after a RESET.
#define SOCCFG_CPUMEMSTART             0x40                                                   // Start address of Memory containing BIOS/Microcode for CPU.
#define SOCCFG_STACKSTART              0x44                                                   // Start address of Memory for Stack use.
// Implementation bits.
#define IMPL_WB                        0x00400000
#define IMPL_WB_SDRAM                  0x00200000
#define IMPL_WB_I2C                    0x00100000
#define IMPL_BRAM                      0x00080000
#define IMPL_RAM                       0x00040000
#define IMPL_INSN_BRAM                 0x00020000
#define IMPL_SDRAM                     0x00010000
#define IMPL_IOCTL                     0x00008000
#define IMPL_PS2                       0x00004000
#define IMPL_SPI                       0x00002000
#define IMPL_SD                        0x00001000
#define IMPL_SD_DEVICE_CNT             0x00000C00
#define IMPL_INTRCTL                   0x00000200
#define IMPL_INTRCTL_CNT               0x000001F0
#define IMPL_TIMER1                    0x00000008
#define IMPL_TIMER1_TIMER_CNT          0x00000007
#define IMPL_SOCCFG                    0x0000000a
// Test macros
#define IS_IMPL_WB                     ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_WB)            >> 22
#define IS_IMPL_WB_SDRAM               ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_WB_SDRAM)      >> 21
#define IS_IMPL_WB_I2C                 ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_WB_I2C)        >> 20
#define IS_IMPL_BRAM                   ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_BRAM)          >> 19
#define IS_IMPL_RAM                    ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_RAM)           >> 18
#define IS_IMPL_INSN_BRAM              ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_INSN_BRAM)     >> 17
#define IS_IMPL_SDRAM                  ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_SDRAM)         >> 16
#define IS_IMPL_IOCTL                  ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_IOCTL)         >> 15
#define IS_IMPL_PS2                    ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_PS2)           >> 14
#define IS_IMPL_SPI                    ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_SPI)           >> 13
#define IS_IMPL_SD                     ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_SD)            >> 12
#define SOCCFG_SD_DEVICES              ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_SD_DEVICE_CNT) >> 10
#define IS_IMPL_INTRCTL                ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_INTRCTL)       >> 9
#define SOCCFG_INTRCTL_CHANNELS        ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_INTRCTL_CNT)   >> 4
#define IS_IMPL_TIMER1                 ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_TIMER1)        >> 3
#define SOCCFG_TIMER1_TIMERS           ((MEMIO32 (SOCCFG_BASE + SOCCFG_DEVIMPL)) & IMPL_TIMER1_TIMER_CNT)
#define IS_IMPL_SOCCFG                 (MEMIO32 (SOCCFG_BASE + SOCCFG_ZPU_ID)) >> 28 & IMPL_SOCCFG
#define SOCCFG(x)                      (MEMIO32 (SOCCFG_BASE + x))

// -------------------------------
// Wishbone Peripheral definition.
// -------------------------------

// I2C Master Controller.
#define I2C_BASE                       IO_ADDR_WB_PERIPHERALS + 0x000
#define I2C0                           0
#define I2C1                           1
#define I2C2                           2
#define I2C3                           3
#define I2C_SPACING                    0x10
#define I2C_PRE_LOW_REGISTER           0x00                                                   // Low byte clock prescaler register  
#define I2C_PRE_HI_REGISTER            0x01                                                   // High byte clock prescaler register 
#define I2C_CTRL_REGISTER              0x02                                                   // Control register                   
#define I2C_TX_REGISTER                0x03                                                   // Transmit byte register             
#define I2C_CMD_REGISTER               0x04                                                   // Command register                   
#define I2C_RX_REGISTER                0x03                                                   // Receive byte register              
#define I2C_STATUS_REGISTER            0x04                                                   // Status register                    
#define I2C(x, y)                      (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + y))
#define I2C_PRE_LOW(x)                 (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_PRE_LOW_REGISTER))     
#define I2C_PRE_HI(x)                  (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_PRE_HI_REGISTER))     
#define I2C_CTRL(x)                    (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_CTRL_REGISTER))
#define I2C_TX(x)                      (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_TX_REGISTER))
#define I2C_CMD(x)                     (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_CMD_REGISTER))
#define I2C_RX(x)                      (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_RX_REGISTER))
#define I2C_STATUS(x)                  (MEMIO32 (I2C_BASE+(x*I2C_SPACING) + I2C_STATUS_REGISTER))
#define I2C_EN (1<<7)                                                                         // Core enable bit:                   
                                                                                              //      1 - core is enabled           
                                                                                              //      0 - core is disabled          
#define OC_I2C_IEN (1<<6)                                                                     // Interrupt enable bit               
                                                                                              //      1 - Interrupt enabled         
                                                                                              //      0 - Interrupt disabled        
                                                                                              // Other bits in CR are reserved      
#define I2C_STA (1<<7)                                                                        // Generate (repeated) start condition
#define I2C_STO (1<<6)                                                                        // Generate stop condition            
#define I2C_RD  (1<<5)                                                                        // Read from slave                    
#define I2C_WR  (1<<4)                                                                        // Write to slave                     
#define I2C_ACK (1<<3)                                                                        // Acknowledge from slave             
                                                                                              //      1 - ACK                       
                                                                                              //      0 - NACK                      
#define I2C_IACK (1<<0)                                                                       // Interrupt acknowledge              
#define I2C_RXACK (1<<7)                                                                      // ACK received from slave            
                                                                                              //      1 - ACK                       
                                                                                              //      0 - NACK                     
#define I2C_BUSY  (1<<6)                                                                      // Busy bit                           
#define I2C_TIP   (1<<1)                                                                      // Transfer in progress               
#define I2C_IF    (1<<0)                                                                      // Interrupt flag                     
#define I2C_IS_SET(reg,bitmask)        ((reg)&(bitmask))
#define I2C_IS_CLEAR(reg,bitmask)      (!(I2C_IS_SET(reg,bitmask)))
#define I2C_BITSET(reg,bitmask)        ((reg)|(bitmask))
#define I2C_BITCLEAR(reg,bitmask)      ((reg)|(~(bitmask)))
#define I2C_BITTOGGLE(reg,bitmask)     ((reg)^(bitmask))
#define I2C_REGMOVE(reg,value)         ((reg)=(value))


// State definitions.
#define INPUT                          1
#define OUTPUT                         0
#define HIGH                           1
#define LOW                            0

// Prototypes.
void setupSoCConfig(void);
void showSoCConfig(void);
void printZPUId(uint32_t);

// Configuration values.
typedef struct
{
    uint32_t                           addrInsnBRAM;
    uint32_t                           sizeInsnBRAM;
    uint32_t                           addrBRAM;
    uint32_t                           sizeBRAM;
    uint32_t                           addrRAM;
    uint32_t                           sizeRAM;
    uint32_t                           addrSDRAM;
    uint32_t                           sizeSDRAM;
    uint32_t                           addrWBSDRAM;
    uint32_t                           sizeWBSDRAM;
    uint32_t                           resetVector;
    uint32_t                           cpuMemBaseAddr;
    uint32_t                           stackStartAddr;
    uint16_t                           zpuId;
    uint32_t                           sysFreq;
    uint32_t                           memFreq;
    uint32_t                           wbMemFreq;
    uint8_t                            implSoCCFG;    
    uint8_t                            implWB;
    uint8_t                            implWBSDRAM;
    uint8_t                            implWBI2C;
    uint8_t                            implInsnBRAM;
    uint8_t                            implBRAM;
    uint8_t                            implRAM;
    uint8_t                            implSDRAM;
    uint8_t                            implIOCTL;
    uint8_t                            implPS2;
    uint8_t                            implSPI;
    uint8_t                            implSD;
    uint8_t                            sdCardNo;
    uint8_t                            implIntrCtl;
    uint8_t                            intrChannels;
    uint8_t                            implTimer1;
    uint8_t                            timer1No;
} SOC_CONFIG;

// Global scope variables.
//extern SOC_CONFIG                     *cfgSoC;

#endif
