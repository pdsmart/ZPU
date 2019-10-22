/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            sharpmz.h
// Created:         December 2018
// Author(s):       Philip Smart
// Description:     IO Control Processor Emulated host definitions header.
//                                                         
// Credits:         
// Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
//
// History:         December 2018  - Initial module written.
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////
// This source file is free software: you can redistribute it and/or modify
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
#ifndef SHARPMZ_H
#define SHARPMZ_H

// Defaults.
//
#define MZ_TAPE_HEADER_STACK_ADDR         0x10f0
#define MZ_TAPE_HEADER_SIZE               128
#define MAX_FILENAME_SIZE                 1024
#define MAX_TAPE_QUEUE                    5

// Memory blocks within the Emulator.
//
#define SHARPMZ_MEMBANK_ALL               0xff
#define SHARPMZ_MEMBANK_SYSROM            0
#define SHARPMZ_MEMBANK_SYSRAM            1
#define SHARPMZ_MEMBANK_KEYMAP            2
#define SHARPMZ_MEMBANK_VRAM              3
#define SHARPMZ_MEMBANK_CMT_HDR           4
#define SHARPMZ_MEMBANK_CMT_DATA          5
#define SHARPMZ_MEMBANK_CGROM             6
#define SHARPMZ_MEMBANK_CGRAM             7
#define SHARPMZ_MEMBANK_MAXBANKS          8

// Name of the configuration file.
//
#define SHARPMZ_CONFIG_FILENAME           "SHARPMZ.CFG"

// Name of the core.
//
#define SHARPMZ_CORE_NAME                 "SharpMZ"

// Maximum number of machines currently supported by the emulation.
//
#define MAX_MZMACHINES                    8

// Maximum number of sub-roms per machine.
//
#define MAX_MROMOPTIONS                   2

// Numeric index of each machine.
//
#define MZ80K_IDX                         0    // 000
#define MZ80C_IDX                         1    // 001
#define MZ1200_IDX                        2    // 010
#define MZ80A_IDX                         3    // 011
#define MZ700_IDX                         4    // 100
#define MZ800_IDX                         5    // 101
#define MZ80B_IDX                         6    // 110
#define MZ2000_IDX                        7    // 111

// Maximum number of images which can be loaded.
//
#define MAX_IMAGE_TYPES                   6

// Numeric index of each main rom image category.
//
#define MROM_IDX                          0
#define MROM_80C_IDX                      1
#define CGROM_IDX                         2
#define KEYMAP_IDX                        3
#define USERROM_IDX                       4
#define FDCROM_IDX                        5

// Numeric index of monitor rom subtypes.
//
#define MONITOR                           0
#define MONITOR_80C                       1

// Numeric index of Option rom subtypes.
//
#define USERROM                           0
#define FDCROM                            1

// Tape(CMT) Data types.
//
#define SHARPMZ_CMT_MC                    1    // machine code program.
#define SHARPMZ_CMT_BASIC                 2    // MZ-80 Basic program.
#define SHARPMZ_CMT_DATA                  3    // MZ-80 data file.
#define SHARPMZ_CMT_700DATA               4    // MZ-700 data file.
#define SHARPMZ_CMT_700BASIC              5    // MZ700 Basic program.

// Tape(CMT) Register bits.
//
#define REGISTER_CMT_PLAY_READY        0x01
#define REGISTER_CMT_PLAYING           0x02
#define REGISTER_CMT_RECORD_READY      0x04
#define REGISTER_CMT_RECORDING         0x08
#define REGISTER_CMT_ACTIVE            0x10
#define REGISTER_CMT_SENSE             0x20
#define REGISTER_CMT_WRITEBIT          0x40
#define REGISTER_CMT2_APSS             0x01
#define REGISTER_CMT2_DIRECTION        0x02
#define REGISTER_CMT2_EJECT            0x04
#define REGISTER_CMT2_PLAY             0x08
#define REGISTER_CMT2_STOP             0x10

// Numeric id of bit for a given CMT register flag.
//
#define CMT_PLAY_READY                    0    // Tape play back buffer, 0 = empty, 1 = full.
#define CMT_PLAYING                       1    // Tape playback, 0 = stopped, 1 = in progress.
#define CMT_RECORD_READY                  2    // Tape record buffer full.
#define CMT_RECORDING                     3    // Tape recording, 0 = stopped, 1 = in progress.
#define CMT_ACTIVE                        4    // Tape transfer in progress, 0 = no activity, 1 = activity.
#define CMT_SENSE                         5    // Tape state Sense out.
#define CMT_WRITEBIT                      6    // Write bit to MZ.
#define CMT_READBIT                       7    // Receive bit from MZ.
#define CMT_MOTOR                         8    // Motor on/off.

// Numeric id of SharpMZ system registers.
//
#define SHARPMZ_REGISTER_BASE             0x01000000
#define REGISTER_MODEL                    0
#define REGISTER_DISPLAY                  1
#define REGISTER_DISPLAY2                 2
#define REGISTER_DISPLAY3                 3
#define REGISTER_CPU                      4
#define REGISTER_AUDIO                    5
#define REGISTER_CMT                      6
#define REGISTER_CMT2                     7
#define REGISTER_USERROM                  8
#define REGISTER_FDCROM                   9
#define REGISTER_10                      10 
#define REGISTER_11                      11 
#define REGISTER_12                      12 
#define REGISTER_SETUP                   13
#define REGISTER_DEBUG                   14
#define REGISTER_DEBUG2                  15 
#define MAX_REGISTERS                    16

// Prototypes.
//

#endif // SHARPMZ_H
