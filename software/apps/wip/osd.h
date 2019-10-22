/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            osd.h
// Created:         December 2018
// Author(s):       Philip Smart
// Description:     IO Control Processor On Screen Display header.
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
#ifndef OSD_H
#define OSD_H

// Debug output enabled by function definition difference.
//
#ifdef DEBUG
#define osd_x_debugf(a, ...) printf(a, ##__VA_ARGS__);
#define osd_debugf(a, ...)   printf(a, ##__VA_ARGS__);
#else
#define osd_debugf(a, ...)
#define osd__x_debugf(a, ...)
#endif

// Status and Menu screen definitions.
//
#define STATUS_SCREEN                    0
#define STATUS_SCREEN_BASE_ADDR          0x320000
#define STATUS_SCREEN_SIZE               4096
#define STATUS_SCREEN_MAX_COLUMNS        80
#define STATUS_SCREEN_LINE_WIDTH         640
#define STATUS_SCREEN_MAX_ROWS           6
#define STATUS_SCREEN_MAX_LINES          51 
#define MENU_SCREEN                      1
#define MENU_SCREEN_BASE_ADDR            0x322000
#define MENU_SCREEN_SIZE                 8192
#define MENU_SCREEN_MAX_COLUMNS          32
#define MENU_SCREEN_MAX_LINES            256
#define MENU_SCREEN_LINE_WIDTH           256
#define MENU_SCREEN_MAX_ROWS             16
#define VIDEO_CONFIG_ADDR                0x324000

// Command/Mode/Status bits.
//
#define CMD_WRITECHAR                    0x20000000                    // 0b00100000000000000000000000000000
#define CMD_READ                         0x40000000                    // 0b01000000000000000000000000000000
#define CMD_WRITE                        0x80000000                    // 0b10000000000000000000000000000000
#define MODE_HALFPIXEL                   0x00200000                    // 0b00000000001000000000000000000000
#define MODE_V2X                         0x00400000                    // 0b00000000010000000000000000000000
#define MODE_H2X                         0x00800000                    // 0b00000000100000000000000000000000
#define MODE_ROTATE_0                    0x00000000                    // 0b00000000000000000000000000000000
#define MODE_ROTATE_90L                  0x01000000                    // 0b00000001000000000000000000000000
#define MODE_ROTATE_90R                  0x02000000                    // 0b00000010000000000000000000000000
#define MODE_ROTATE_180                  0x03000000                    // 0b00000011000000000000000000000000
#define MODE_BG_GREEN                    0x04000000                    // 0b00000100000000000000000000000000
#define MODE_BG_RED                      0x08000000                    // 0b00001000000000000000000000000000
#define MODE_BG_BLUE                     0x10000000                    // 0b00010000000000000000000000000000
#define MODE_FG_GREEN                    0x20000000                    // 0b00100000000000000000000000000000
#define MODE_FG_RED                      0x40000000                    // 0b01000000000000000000000000000000
#define MODE_FG_BLUE                     0x80000000                    // 0b10000000000000000000000000000000
#define STATUS_BUSY_WRITECHAR            0x20000000                    // 0b00100000000000000000000000000000
#define STATUS_DATA_AVAIL                0x40000000                    // 0b01000000000000000000000000000000
#define STATUS_BUSY_WRITE                0x80000000                    // 0b10000000000000000000000000000000

// Character Generator Sets and addresses in the Emulator ROM.
//
#define CG_MZ80K                         0
#define CG_MZ80C                         1
#define CG_MZ1200                        2
#define CG_MZ80A                         3
#define CG_MZ700LO                       4
#define CG_MZ700HI                       5
#define CG_MZ800LO                       6
#define CG_MZ800HI                       7
#define CG_MZ80B                         8
#define CG_MZ2000                        9
#define MAX_CHARGEN_SETS                 10
static const uint32_t CHARGENADDR[MAX_CHARGEN_SETS] =
                                           { 0x500000, 0x501000, 0x502000, 0x502800, 0x503000, 0x503800, 0x504000, 0x505000, 0x506000, 0x507000 };

// Attributes definitions.
//
#define CG_ROTATE_NORMAL                 0
#define CG_ROTATE_90L                    1
#define CG_ROTATE_90R                    2
#define CG_ROTATE_180                    3
#define MAX_ROTATIONS                    4
static const uint32_t ROTATIONMAP[MAX_ROTATIONS] = { MODE_ROTATE_0, MODE_ROTATE_90L, MODE_ROTATE_90R, MODE_ROTATE_180 };
#define CG_HORZOOM_NORMAL                0
#define CG_HORZOOM_X2                    1
#define MAX_HORIZONTAL_ZOOM              2
static const uint32_t HORZOOMMAP[MAX_HORIZONTAL_ZOOM] = { 0x0, MODE_H2X };
#define CG_VERZOOM_NORMAL                0
#define CG_VERZOOM_X2                    1
#define MAX_VERTICAL_ZOOM                2
static const uint32_t VERZOOMMAP[MAX_VERTICAL_ZOOM] = { 0x0, MODE_V2X };
#define CG_PIXEL_SETTING_NORMAL          0
#define CG_PIXEL_SETTING_HALF            1
#define MAX_PIXEL_SETTINGS               2
static const uint32_t PIXELSETTINGMAP[MAX_PIXEL_SETTINGS] = { 0x0, MODE_HALFPIXEL };
#define CG_BLACK                         0
#define CG_BLUE                          1
#define CG_GREEN                         2
#define CG_CYAN                          3
#define CG_RED                           4
#define CG_PURPLE                        5
#define CG_YELLOW                        6
#define CG_WHITE                         7
#define MAX_COLOURS                      8
static const uint32_t STATUSFGCOLOURS[MAX_COLOURS] = { 0x00000000, MODE_FG_BLUE, MODE_FG_GREEN, MODE_FG_BLUE | MODE_FG_GREEN, MODE_FG_RED, MODE_FG_RED | MODE_FG_BLUE, MODE_FG_RED | MODE_FG_GREEN, MODE_FG_BLUE | MODE_FG_GREEN | MODE_FG_RED };
static const uint32_t STATUSBGCOLOURS[MAX_COLOURS] = { 0x00000000, MODE_BG_BLUE, MODE_BG_GREEN, MODE_BG_BLUE | MODE_BG_GREEN, MODE_BG_RED, MODE_BG_RED | MODE_BG_BLUE, MODE_BG_RED | MODE_BG_GREEN, MODE_BG_BLUE | MODE_BG_GREEN | MODE_BG_RED };

// Registers
//
#define REGISTER_CMDADDR                 0
#define REGISTER_DOUT                    1
#define REGISTER_DIN                     1
#define REGISTER_CHRCOLS                 2
#define REGISTER_CHRCFG                  3
#define REGISTER_CGADDR                  4

// Structure to hold control parameters per screen area.
//
typedef struct
{
    uint32_t            rotation;
    uint32_t            horizontalZoom;
    uint32_t            verticalZoom;
    uint32_t            halfPixels;
    uint32_t            fgColour;
    uint32_t            bgColour;
    uint32_t            cgAddr;
    uint32_t            cgAttr;
    uint32_t            charAddr;
    uint32_t            colMult;
    uint32_t            rowMult;
    uint32_t            col;
    uint32_t            row;
    uint32_t            enabled;
} screen_t;

// Prototypes.
//
void                   osdInit(void);
void                   setConfigRegister(uint32_t, uint32_t);
void                   osdFillStatus(uint32_t, uint16_t, uint16_t);
void                   osdClearStatus(void);
void                   osdFillMenu(uint32_t, uint16_t, uint16_t);
void                   osdClearMenu(void);
void                   osdClearScreen(void);
void                   osdSelectCG(uint32_t, uint32_t);
void                   osdSetCGAttr(uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
uint32_t               osdGetRow(uint32_t);
uint32_t               osdGetColumn(uint32_t);
void                   osdSetPosition(uint32_t, uint32_t, uint32_t);
void                   osdEnable(uint32_t, uint32_t);
uint8_t                osdWriteChar(uint8_t, uint8_t, uint8_t);



#endif // OSD_H
