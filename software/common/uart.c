#include "zpu-types.h"
#include "zpu_soc.h"
#include "uart.h"

static uint8_t uart_channel = 0;
__inline void set_serial_output(uint8_t c)
{
    uart_channel = (c == 0 ? 0 : 1);
}

__inline int putchar(int c)
{
    uint32_t status;

    do {
        status = UART_STATUS(uart_channel == 0 ? UART0 : UART1);
    } while((UART_IS_TX_FIFO_ENABLED(status) && UART_IS_TX_FIFO_FULL(status)) || (UART_IS_TX_FIFO_DISABLED(status) && UART_IS_TX_DATA_LOADED(status)));
    UART_DATA(uart_channel == 0 ? UART0 : UART1) = c;

    return(c);
}

__inline void _putchar(unsigned char c)
{
    putchar(c);
}

#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 2
__inline int dbgputchar(int c)
{
    uart_channel = 1;
    putchar(c);
    uart_channel = 0;

    return(c);
}

__inline void _dbgputchar(unsigned char c)
{
    dbgputchar(c);
}
#endif

#ifdef USELOADB
int puts(const char *msg)
{
    int result = 0;

    while (*msg) {
		putchar(*msg++);
        ++result;
	}
    return(result);
}
#else
int puts(const char *msg)
{
    int c;
    int result=0;
    // Because we haven't implemented loadb from ROM yet, we can't use *<char*>++.
    // Therefore we read the source data in 32-bit chunks and shift-and-split accordingly.
    int *s2=(int*)msg;

    do
    {
        int i;
        int cs=*s2++;
        for(i=0;i<4;++i)
        {
            c=(cs>>24)&0xff;
            cs<<=8;
            if(c==0)
                return(result);
            putchar(c);
            ++result;
        }
    }
    while(c);
    return(result);
}
#endif

#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
char getserial()
{
    uint32_t reg;

    do {
        reg = UART_STATUS(uart_channel == 0 ? UART0 : UART1);
    } while(!UART_IS_RX_DATA_READY(reg));
    reg=UART_DATA(uart_channel == 0 ? UART0 : UART1);

    return((char)reg & 0xFF);
}

int8_t getserial_nonblocking()
{
    int8_t reg;

    reg = UART_STATUS(uart_channel == 0 ? UART0 : UART1);
    if(!UART_IS_RX_DATA_READY(reg))
    {
        reg = -1;
    }
    else
    {
        reg = UART_DATA(uart_channel == 0 ? UART0 : UART1);
    }

    return(reg);
}

char getdbgserial()
{
    int32_t reg = 0;

    set_serial_output(1);
    reg = getserial();
    set_serial_output(0);
    return((char)reg & 0xFF);
}

int8_t getdbgserial_nonblocking()
{
    int8_t reg = 0;

    set_serial_output(1);
    reg = getserial_nonblocking();
    set_serial_output(0);
    return(reg);
}
#endif
