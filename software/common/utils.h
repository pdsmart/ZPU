////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            utils.h
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
#ifndef UTILS_H
#define UTILS_H

#ifdef __cplusplus
extern "C" {
#endif

// Real time clock structure, maps to the underlying hardware.
typedef struct {
    uint16_t    year;    /* 2000..2099 */
    uint8_t     month;   /* 1..12 */
    uint8_t     day;     /* 1.. 31 */
    uint8_t     hour;    /* 0..23 */
    uint8_t     min;     /* 0..59 */
    uint8_t     sec;     /* 0..59 */
    uint16_t    msec;    /* 0..999 */
    uint16_t    usec;    /* 0..999 */
} RTC;    

// Prototypes
void          printnibble(uint8_t c);
void          printhexbyte(uint8_t c);
void          printhex(uint32_t c);
void          printdhex(uint32_t c);
unsigned int  crc32_init(void);
unsigned int  crc32_addword(unsigned int, unsigned int);
unsigned int  get_dword(void);
char         *getStrParam(char **);
uint32_t      getUintParam(char **ptr);
uint8_t       rtcSet(RTC *);
void          rtcGet(RTC *);    

// Debug only macros which dont generate code when debugging disabled.
#ifdef DEBUG

    // Macro to print out hex data to the debug channel.
    //
    #define dbg_printnibble(a) ({\
                set_serial_output(1);\
                printnibble(a);\
                set_serial_output(0);\
               })
    #define dbg_printhexbyte(a) ({\
                set_serial_output(1);\
                printhexbyte(a);\
                set_serial_output(0);\
               })
    #define dbg_printhex(a) ({\
                set_serial_output(1);\
                printhex(a);\
                set_serial_output(0);\
               })
    #define dbg_printdhex(a) ({\
                set_serial_output(1);\
                printdhex(a);\
                set_serial_output(0);\
               })

#else

    #define dbg_printnibble(a)
    #define dbg_printhexbyte(a)
    #define dbg_printhex(a)
    #define dbg_printdhex(a)

#endif

#ifdef __cplusplus
}
#endif

#endif

