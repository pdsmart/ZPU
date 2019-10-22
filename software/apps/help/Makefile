#########################################################################################################
##
## Name:            Makefile
## Created:         July 2019
## Author(s):       Philip Smart
## Description:     App Makefile - Build an App for the ZPU Test Application (zputa)
##                  This makefile builds an app which is stored on an SD card and called by the ZPUTA
##                  test application. The app generally is for testing some component where the code is
##                  not built into ZPUTA or memory restrictions prohibit it being built in.
##
## Credits:         
## Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
##
## History:         July 2019   - Initial Makefile created for template use.
##
## Notes:           Optional component enables:
##                  USELOADB              - The Byte write command is implemented in hw#sw so use it.
##                  USE_BOOT_ROM          - The target is ROM so dont use initialised data.
##                  MINIMUM_FUNTIONALITY  - Minimise functionality to limit code size.
##                  COREMARK_TEST         - Add the CoreMark test suite.
##                  DHYRSTONE_TEST        - Add the Dhrystone test suite.
##                  USE_SDCARD            - Add the SDCard logic.
##
#########################################################################################################
## This source file is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This source file is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
#########################################################################################################

APP_NAME       = help
APP_DIR        = ..
BASEDIR        = ../../..

# Enable CoreMark Test
OFLAGS        += -DCOREMARK_TEST
# Enable Dhrystone Test
OFLAGS        += -DDHRYSTONE_TEST

include        $(APP_DIR)/Makefile.inc
