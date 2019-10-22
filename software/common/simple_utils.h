////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            simple_utils.h
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
#ifndef SIMPLE_UTILS_H
#define SIMPLE_UTILS_H

#ifdef __cplusplus
extern "C" {
#endif

// Prototypes
void printnibble(uint8_t c);
void printhexbyte(uint8_t c);
void printhex(uint32_t c);
void printdhex(uint32_t c);
int memoryDump(uint32_t, uint32_t);
unsigned int crc32_init(void);
unsigned int crc32_addword(unsigned int, unsigned int);
unsigned int get_dword(void);


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

#ifdef __cplusplus
}
#endif

#endif

