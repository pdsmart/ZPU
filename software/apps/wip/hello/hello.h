/////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            hello.h
// Created:         July 2018
// Author(s):       Philip Smart
// Description:     Standalone App for the ZPU test application.
//                                                         
// Credits:         
// Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
//
// History:         July 2019  - Initial framework created.
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
#ifndef HELLO_H
#define HELLO_H

// Constants.

// Application execution constants.
//

// Prototypes.
uint32_t app(uint32_t, uint32_t);

// Global scope variables within the ZPUTA memory space.
GLOBALS                      *G;
SOC_CONFIG                  *cfgSoC;

// Global scope variables in the app memory space.
volatile UINT                Timer;                                    /* Performance timer (100Hz increment) */

#endif // HELLO_H
