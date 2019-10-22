////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            simple_utils.c
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPU boottime simple utilities.
//                  A set of utilities to be used in the IOCP (or other minimalist application) which
//                  assume a minimum compile environment (ie. no printf)such that the smallest code
//                  size is created.
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
#include "zpu-types.h"
#include "zpu_soc.h"
#include "uart.h"

// Functions, in the absense of printf, to output a value as hex.
//  Nibble :- a single digit 0-f
void printnibble(uint8_t c)
{
    c&=0xf;
    if (c>9)
        putchar(c+'a'-10);
    else
        putchar(c+'0');
}
// Byte: 8 bits represented by 2 digits, <0-f><0-f>
void printhexbyte(uint8_t c)
{
    printnibble(c>>4);
    printnibble(c);
}
// Half Word: 16 bits represented by 4 digits.
void printhex(uint32_t c)
{
    printhexbyte((uint8_t)(c>>8));
    printhexbyte((uint8_t)(c));
}
// Word: 32 bits represented by 8 digits.
void printdhex(uint32_t c)
{
    printhexbyte((uint8_t)(c>>24));
    printhexbyte((uint8_t)(c>>16));
    printhexbyte((uint8_t)(c>>8));
    printhexbyte((uint8_t)(c));
}


// Function to dump out a given section of memory via the currently selected UART.
//
#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
int memoryDump(uint32_t memaddr, uint32_t memsize)
{
  uint32_t pnt = memaddr;
  uint32_t i = 0;
  uint32_t data;
  char c = 0;

  while (1)
  {
    printdhex(pnt); // print address
    puts(":  ");

    // print hexadecimal data
    for (i=0; i < 32; i++) {
        printhexbyte(*(uint8_t *)(pnt+i));
        putchar((char)' ');
    }
 
    // print ascii data
    puts(" |");

    // print single ascii char
    for (i=0; i < 32; i++) {
      c = (char)*(uint8_t *)(pnt+i);
      if ((c >= ' ') && (c <= '~'))
        putchar((char)c);
      else
        putchar((char)' ');
    }

    puts("|\n");

    // Move on one row.
    pnt += 16;

    // user abort or all done?
    if ((getserial_nonblocking() != -1) || (pnt >= (memaddr + memsize)))
    {
        return(0);
    }

  }

  // Normal exit, return -1 to show no key pressed.
  return(-1);
}
#endif

// Function to setup the CRC polynomial table prior to use.
//
#if !defined(FUNCTIONALITY) || FUNCTIONALITY == 0
static unsigned int crc32table[256];
unsigned int crc32_init(void)
{
    int j;
    unsigned int byte, crc, mask;

    for(byte = 0; byte <= 255; byte++)
    {
        crc = byte;
        for (j = 7; j >= 0; j--)
        {
           mask = -(crc & 1);
           crc = (crc >> 1) ^ (0xEDB88320 & mask);
        }
        crc32table[byte] = crc;
    }

    // Starting value for CRC calculation.
    //
    return 0xFFFFFFFF;
}

// Function to add a word into the CRC sum.
//
unsigned int crc32_addword(unsigned int crc_in, unsigned int word)
{
   crc_in = (crc_in >> 8) ^ crc32table[(crc_in ^ ((word >> 24)&0xFF)) & 0xFF];
   crc_in = (crc_in >> 8) ^ crc32table[(crc_in ^ ((word >> 16)&0xFF)) & 0xFF];
   crc_in = (crc_in >> 8) ^ crc32table[(crc_in ^ ((word >>  8)&0xFF)) & 0xFF];
   crc_in = (crc_in >> 8) ^ crc32table[(crc_in ^ (word        &0xFF)) & 0xFF];

   return crc_in;
}

// Function to read a 32bit word from the active serial port.
//
unsigned int get_dword(void)
{
    unsigned int temp = 0;
    int idx;

    for(idx=0; idx < 4; idx++)
    {
        temp = (temp << 8) | (unsigned int)getserial();
    }

    return(temp);
}
#endif
