/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            osd.c
// Created:         December 2018
// Author(s):       Philip Smart
// Description:     IO Control Processor On Screen Display interface.
//                  This module provides the routines to display data on the status and menu portions
//                  of the Emulation host screen.
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
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#include "zpu-types.h"
#include "zpu_soc.h"
#include "osd.h"
#include "sharpmz.h"
//#include "../lib/storm_core.h"
//#include "../lib/storm_soc_basic.h"

// Internal variables.
//
static screen_t statusScreen;
static screen_t menuScreen;

// Method to perform any initialization.
//
void osdInit(void)
{

    // Status screen control parameters.
    statusScreen.rotation        = CG_ROTATE_NORMAL;
    statusScreen.horizontalZoom  = CG_HORZOOM_NORMAL;
    statusScreen.verticalZoom    = CG_VERZOOM_NORMAL;
    statusScreen.halfPixels      = CG_PIXEL_SETTING_NORMAL;
    statusScreen.fgColour        = CG_WHITE;
    statusScreen.bgColour        = CG_BLACK;
    statusScreen.cgAddr          = CHARGENADDR[CG_MZ80A];
    statusScreen.cgAttr          = 0x00000000;
    statusScreen.colMult         = 1;
    statusScreen.rowMult         = 1;
    statusScreen.col             = 0;
    statusScreen.row             = 0;
    statusScreen.enabled         = 0;

    // Menu screen control parameters.
    menuScreen.rotation          = CG_ROTATE_NORMAL;
    menuScreen.horizontalZoom    = CG_HORZOOM_NORMAL;
    menuScreen.verticalZoom      = CG_VERZOOM_NORMAL;
    menuScreen.halfPixels        = CG_PIXEL_SETTING_NORMAL;
    menuScreen.fgColour          = CG_WHITE;
    menuScreen.bgColour          = CG_BLACK;
    menuScreen.cgAddr            = CHARGENADDR[CG_MZ80A];
    menuScreen.cgAttr            = 0x00000000;
    menuScreen.colMult           = 1;
    menuScreen.rowMult           = 1;
    menuScreen.col               = 0;
    menuScreen.row               = 0;
    menuScreen.enabled           = 0;
}

// Method to program a config register in the emulator.
//
void setConfigRegister(uint32_t addr, uint32_t value)
{
    // Locals.
    uint32_t   din;

    // Wait for any previous transmission to complete.
    //
    do {
        din = IOCTL_CMDADDR;
    } while( din  & STATUS_BUSY_WRITE );

    // Setup the data, then issue write command.
    //
    IOCTL_DOUT    = (uint32_t)value & 0x000000ff;
    IOCTL_CMDADDR = CMD_WRITE | ((SHARPMZ_REGISTER_BASE + addr) & 0x0FFFFFFF);
}

// Method to fill the status screen frame buffer memory with a fixed colour.
//
void osdFillStatus(uint32_t colour, uint16_t startLine, uint16_t endLine)
{
    // Locals
    uint32_t din;
    uint32_t u;

    // Sanity checks.
    if(startLine > STATUS_SCREEN_MAX_LINES) startLine = STATUS_SCREEN_MAX_LINES;
    if(endLine   > STATUS_SCREEN_MAX_LINES) endLine   = STATUS_SCREEN_MAX_LINES;

    // Use columns as each byte is 8 pixels wide.
    for(u=startLine*STATUS_SCREEN_MAX_COLUMNS; u < endLine*STATUS_SCREEN_MAX_COLUMNS; u++)
    {
        // Wait until last operation completes before next.
        while( ((din = IOCTL_CMDADDR) & STATUS_BUSY_WRITE) );

        // Load output with required fill colour.
        IOCTL_DOUT = colour & 0x00ffffff;

        // Send command to write to one set of 8 pixels.
        IOCTL_CMDADDR = CMD_WRITE | ((STATUS_SCREEN_BASE_ADDR + u) & 0x0FFFFFFF);
    }
}

// Method to clear the status screen frame buffer memory.
//
void osdClearStatus(void)
{
    osdFillStatus(0x00000000, 0, STATUS_SCREEN_MAX_LINES);
}

// Method to fill the menu screen frame buffer memory with a fixed colour.
//
void osdFillMenu(uint32_t colour, uint16_t startLine, uint16_t endLine)
{
    // Locals
    uint32_t din;
    uint32_t u;

    // Sanity checks.
    if(startLine > MENU_SCREEN_MAX_LINES) startLine = MENU_SCREEN_MAX_LINES;
    if(endLine   > MENU_SCREEN_MAX_LINES) endLine   = MENU_SCREEN_MAX_LINES;

    // Use columns as each byte is 8 pixels wide.
    for(u=startLine*MENU_SCREEN_MAX_COLUMNS; u < endLine*MENU_SCREEN_MAX_COLUMNS; u++)
    {
        // Wait until last operation completes before next.
        while( ((din = IOCTL_CMDADDR) & STATUS_BUSY_WRITE) );

        // Load output required fill, colour is set by mctrl registers.
        IOCTL_DOUT = colour & 0x000000ff;

        // Send command to write to one set of 8 pixels.
        IOCTL_CMDADDR = CMD_WRITE | ((MENU_SCREEN_BASE_ADDR + u) & 0x0FFFFFFF);
    }
}

// Method to clear the menu screen frame buffer memory.
//
void osdClearMenu(void)
{
    osdFillMenu(0x00000000,   0, MENU_SCREEN_MAX_LINES);
}

// Method to clear the status and menu screen frame buffer memorys.
//
void osdClearScreen(void)
{
    osdFillStatus(0x00000000, 0, STATUS_SCREEN_MAX_LINES);
    osdFillMenu(0x00000000,   0, MENU_SCREEN_MAX_LINES);
}

// Method to setup the address of the required character generator rom.
//
void osdSelectCG(uint32_t screen, uint32_t charGenSet)
{
    // Sanity check.
    if(charGenSet >= MAX_CHARGEN_SETS)
        charGenSet = CG_MZ80A;

    // Save the parameters.
    if(screen == STATUS_SCREEN)
    {
        statusScreen.cgAddr          = CHARGENADDR[charGenSet];
    } else
    {
        menuScreen.cgAddr            = CHARGENADDR[charGenSet];
    }
}

// Method to setup the attributes for future character writes.
//
void osdSetCGAttr(uint32_t screen, uint32_t rotation, uint32_t horizontalZoom, uint32_t verticalZoom, uint32_t halfPixels, uint32_t fgColour, uint32_t bgColour)
{
    // Locals.
    uint32_t cgAttr;
    uint32_t rowMult;
    uint32_t colMult;

    // Sanity check.
    if(screen != STATUS_SCREEN && screen != MENU_SCREEN)
        return;
    if(rotation >= MAX_ROTATIONS)
        rotation = CG_ROTATE_NORMAL;
    if(horizontalZoom >= MAX_HORIZONTAL_ZOOM)
        horizontalZoom = CG_HORZOOM_NORMAL;
    if(verticalZoom >= MAX_VERTICAL_ZOOM)
        verticalZoom = CG_VERZOOM_NORMAL;
    if(halfPixels >= MAX_PIXEL_SETTINGS)
        halfPixels = CG_PIXEL_SETTING_NORMAL;
    if(fgColour >= MAX_COLOURS)
        fgColour = CG_WHITE;
    if(bgColour >= MAX_COLOURS)
        bgColour = CG_BLACK;

    // Setup the attributes for future character writes.
    cgAttr = STATUSFGCOLOURS[fgColour] | STATUSBGCOLOURS[bgColour] | ROTATIONMAP[rotation] | HORZOOMMAP[horizontalZoom] | VERZOOMMAP[verticalZoom] | PIXELSETTINGMAP[halfPixels];
    
    // Setup the control parameters.
    colMult = horizontalZoom == CG_HORZOOM_NORMAL ? 1 : 2;
    rowMult = verticalZoom   == CG_VERZOOM_NORMAL ? 1 : 2;

    // Save the parameters.
    if(screen == STATUS_SCREEN)
    {
        statusScreen.rotation        = rotation;
        statusScreen.horizontalZoom  = horizontalZoom;
        statusScreen.verticalZoom    = verticalZoom;
        statusScreen.halfPixels      = halfPixels;
        statusScreen.fgColour        = fgColour;
        statusScreen.bgColour        = bgColour;
        statusScreen.cgAttr          = cgAttr;
        statusScreen.colMult         = colMult;
        statusScreen.rowMult         = rowMult;
    } else
    {
        menuScreen.rotation          = rotation;
        menuScreen.horizontalZoom    = horizontalZoom;
        menuScreen.verticalZoom      = verticalZoom;
        menuScreen.halfPixels        = halfPixels;
        menuScreen.fgColour          = fgColour;
        menuScreen.bgColour          = bgColour;
        menuScreen.cgAttr            = cgAttr;
        menuScreen.colMult           = colMult;
        menuScreen.rowMult           = rowMult;
    }
}

// Method to return current row.
//
uint32_t osdGetRow(uint32_t screen)
{
    // Sanity check.
    if(screen != STATUS_SCREEN && screen != MENU_SCREEN)
        return(0);

    return(screen = STATUS_SCREEN ? statusScreen.row : menuScreen.row);
}

// Method to return current column.
//
uint32_t osdGetColumn(uint32_t screen)
{
    // Sanity check.
    if(screen != STATUS_SCREEN && screen != MENU_SCREEN)
        return(0);

    return(screen = STATUS_SCREEN ? statusScreen.col : menuScreen.col);
}

// Method to set the screen position for next character write.
//
void osdSetPosition(uint32_t screen, uint32_t row, uint32_t col)
{
    // Sanity check.
    if(screen != STATUS_SCREEN && screen != MENU_SCREEN)
        return;

    if(screen == STATUS_SCREEN)
    {
        if(row >= STATUS_SCREEN_MAX_ROWS)
            row = 0;
        if(col >= STATUS_SCREEN_MAX_COLUMNS)
            col = 0;
        statusScreen.row = row;
        statusScreen.col = col;
    } else
    {
        if(row >= MENU_SCREEN_MAX_ROWS)
            row = 0;
        if(col >= MENU_SCREEN_MAX_COLUMNS)
            col = 0;
        menuScreen.row = row;
        menuScreen.col = col;
    }
}

// Method to make visible (enable) a screen buffer.
//
void osdEnable(uint32_t screen, uint32_t enable)
{
    // Sanity check.
    if(screen != STATUS_SCREEN && screen != MENU_SCREEN)
        return;
    if(enable != 0 && enable != 1)
        enable = 0;

    if(screen == STATUS_SCREEN)
    {
        statusScreen.enabled = enable;
    } else
    {
        menuScreen.enabled = enable;
    }
    // Set the state into the emulator control registers.
    setConfigRegister(REGISTER_DISPLAY3, (statusScreen.enabled << 1) | menuScreen.enabled );
}

// Method to write a character onto the screen buffers.
// Returns: 0 = Normal write.
//          bit 1 = 1 - Column wrapped around to 0.
//          bit 2 = 1 - Row wrapped around to 0.
//
uint8_t osdWriteChar(uint8_t screen, uint8_t dispChar, uint8_t mapToAscii)
{
    // Locals
    uint32_t lineWrap = 0;

    // Sanity check.
    if(screen != STATUS_SCREEN && screen != MENU_SCREEN)
        return(lineWrap);
    if(mapToAscii > 1)
        mapToAscii = 0;
    
    // Process any specific framebuffer settings first.
    if(screen == STATUS_SCREEN)
    {
        IOCTL_CHRCOLS = STATUS_SCREEN_MAX_COLUMNS;
        IOCTL_CGADDR  = statusScreen.cgAddr;
        IOCTL_DOUT    = statusScreen.cgAttr | dispChar;
        statusScreen.charAddr = (STATUS_SCREEN_BASE_ADDR + (statusScreen.row * STATUS_SCREEN_LINE_WIDTH) + statusScreen.col) & 0x0FFFFFFF;
        IOCTL_CMDADDR = CMD_WRITECHAR | statusScreen.charAddr;
      //      uart0_printf("CMDADDR=");
       //     uart0_print_hex_dword(IOCTL_CMDADDR);
        //    uart0_printf("\r\n");
        statusScreen.col += statusScreen.colMult;
        if(statusScreen.col >= STATUS_SCREEN_MAX_COLUMNS)
        {
            lineWrap |= 1;
            statusScreen.col = 0;
            statusScreen.row += statusScreen.rowMult;
            if(statusScreen.row >= STATUS_SCREEN_MAX_ROWS)
            {
                lineWrap |= 2;
                statusScreen.row = 0;
            }
        }
    } else
    {
        IOCTL_CHRCOLS = MENU_SCREEN_MAX_COLUMNS;
        IOCTL_CGADDR  = menuScreen.cgAddr;
        IOCTL_DOUT    = menuScreen.cgAttr | dispChar;
//IOCTL_CMDADDR = CMD_WRITECHAR | (MENU_SCREEN_BASE_ADDR + (((menuScreen.row * MENU_SCREEN_LINE_WIDTH * menuScreen.rowMult) + menuScreen.col * menuScreen.colMult) & 0x0FFFFFFF));
        //menuScreen.charAddr = (MENU_SCREEN_BASE_ADDR + (menuScreen.row * MENU_SCREEN_LINE_WIDTH) + menuScreen.col) & 0x0FFFFFFF;
        menuScreen.charAddr = (MENU_SCREEN_BASE_ADDR + menuScreen.row + menuScreen.col) & 0x0FFFFFFF;
        IOCTL_CMDADDR = CMD_WRITECHAR | menuScreen.charAddr;
            uart0_printf("CMDADDR=");
            uart0_print_hex_dword(IOCTL_CMDADDR);
//            uart0_printf(",ADDR=");
//            uart0_print_hex_dword(charAddr);
//            uart0_printf(",ROW=");
//            uart0_print_hex_byte(menuScreen.row);
//            uart0_printf(",COL=");
//            uart0_print_hex_byte(menuScreen.col);
//            uart0_printf(",DISPCHAR=");
//            uart0_print_hex_dword(dispChar);
            uart0_printf("\r\n");
        menuScreen.col += menuScreen.colMult;
        if(menuScreen.col >= MENU_SCREEN_MAX_COLUMNS)
        {
            menuScreen.col = 0;
            menuScreen.row += menuScreen.rowMult;
            lineWrap |= 1;
            if(menuScreen.row >= MENU_SCREEN_MAX_ROWS)
            {
                lineWrap = 2;
                menuScreen.row = 0;
            }
        }
    }
    
    // Write the character once the IO processor is idle.
    while( (IOCTL_CMDADDR & STATUS_BUSY_WRITECHAR) != 0 );

    // Return any line wrap actions which occurred to the position.
    return(lineWrap);
}
