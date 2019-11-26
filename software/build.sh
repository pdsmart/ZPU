#!/bin/bash
#========================================================================================================
# NAME
#     build.sh -  Shell script to build a ZPU program or OS.
#
# SYNOPSIS
#     build.sh [-CIOoMBAsdxh]
#
# DESCRIPTION
#
# OPTIONS
#     -C <CPU>      = Small, Medium, Flex, Evo - defaults to Evo.
#     -I <iocp ver> = 0 - Full, 1 - Medium, 2 - Minimum, 3 - Tiny (bootstrap only)
#     -O <os>       = zputa, zos
#     -o <os ver>   = 0 - Standalone, 1 - As app with IOCP Bootloader,
#                     2 - As app with tiny IOCP Bootloader, 3 - As app in RAM 
#     -M <size>     = Max size of the boot ROM/BRAM (needed for setting Stack).
#     -B <addr>     = Base address of <os>, default -o == 0 : 0x00000 else 0x01000 
#     -A <addr>     = App address of <os>, default 0x0C000
#     -s <size>     = Maximum size of an app, defaults to (BRAM SIZE - App Start Address - Stack Size) 
#                     if the App Start is located within BRAM otherwise defaults to 0x10000.
#     -d            = Debug mode.
#     -x            = Shell trace mode.
#     -h            = This help screen.
#
# EXAMPLES
#     build.sh -O zputa -B 0x00000 -A 0x50000
#
# EXIT STATUS
#      0    The command ran successfully
#
#      >0    An error ocurred.
#
#EndOfUsage <- do not remove this line
#========================================================================================================
# History:
#          v1.00         : Initial version (C) P. Smart January 2019.
#          v1.10         : Changes to better calculate mode and addresses and setup linker scripts.
#          v1.11         : Added CPU as it is clear certain features must be disabled in the original
#                          CPU's, ie. small where the emulated mul and div arent working as they should.
#========================================================================================================
# This source file is free software: you can redistribute it and#or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This source file is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#========================================================================================================

PROG=${0##*/}
#PARAMS="`basename ${PROG} '.sh'`.params"
ARGS=$*

##############################################################################
# Load program specific variables
##############################################################################

# VERSION of this RELEASE.
#
VERSION="1.10"

# Constants.
BUILDPATH=`pwd`

# Temporary files.
TMP_DIR=/tmp
TMP_OUTPUT_FILE=${TMP_DIR}/tmpoutput_$$.log
TMP_STDERR_FILE=${TMP_DIR}/tmperror_$$.log

# Log mechanism setup.
#
LOG="/tmp/${PROG}_`date +"%Y_%m_%d"`.log"
LOGTIMEWIDTH=40
LOGMODULE="MAIN"

# Mutex's - prevent multiple threads entering a sensitive block at the same time.
#
MUTEXDIR="/var/tmp"

##############################################################################
# Utility procedures
##############################################################################

# Function to output Usage instructions, which is soley a copy of this script header.
#
function Usage
{
    # Output the lines at the start of this script from NAME to EndOfUsage
    cat $0 | nawk 'BEGIN {s=0} /EndOfUsage/ { exit } /NAME/ {s=1} { if (s==1) print substr( $0, 3 ) }'
    exit 1
}

# Function to output a message in Log format, ie. includes date, time and issuing module.
#
function Log
{
	DATESTR=`date "+%d/%m/%Y %H:%M:%S"`
    PADLEN=`expr ${LOGTIMEWIDTH} + -${#DATESTR} + -1 + -${#LOGMODULE} + -5`
	printf "%s %-${PADLEN}s %s\n" "${DATESTR} [$LOGMODULE]" " " "$*"
}

# Function to terminate the script after logging an error message.
#
function Fatal
{
    Log "ERROR: $*"
    Log "$PROG aborted"
    exit 1
}

# Function to output the Usage, then invoke Fatal to exit with a terminal message.
#
function FatalUsage
{
    # Output the lines at the start of this script from NAME to EndOfUsage
    cat $0 | nawk 'BEGIN {s=0} /EndOfUsage/ { exit } /NAME/ {s=1} { if (s==1) print substr( $0, 3 ) }'
    echo " "
    echo "ERROR: $*"
    echo "$PROG aborted"
    exit 1
}

# Function to output a message if DEBUG mode is enabled. Primarily to see debug messages should a
# problem occur.
#
function Debug
{
    if [ $DEBUGMODE -eq 1 ]; then
        Log "$*"
    fi
}

# Function to output a file if DEBUG mode is enabled.
#
function DebugFile
{
    if [ $DEBUGMODE -eq 1 ]; then
        cat $1
    fi
}

# Take an input value to be hex, validate it and format correctly.
function getHex
{
    local __resultvar=$2
    local inputHex=`echo $1 | tr 'a-z' 'A-Z'|sed 's/0X//g'`
    TEST=$(( 16#$inputHex )) 2> /dev/null 
    if [ $? != 0 ]; then
        FatalUsage "Value:$1 is not hexadecimal."
    fi
    local decimal=`echo "16 i $inputHex p" | dc`
    local outputHex=`printf '0x%06X' "$((10#$decimal))"`
    eval $__resultvar="'$outputHex'"
}

# Add two hexadecimal values of the form result = 0xAAAAAA + 0xBBBBBB
function addHex
{
    local __resultvar=$3
    local inputHex1=`echo $1 | tr 'a-z' 'A-Z'|sed 's/0X//g'`
    TEST=$(( 16#$inputHex1 )) 2> /dev/null 
    if [ $? != 0 ]; then
        FatalUsage "Param 1:$1/$inputHex1 is not hexadecimal."
    fi
    local inputHex2=`echo $2 | tr 'a-z' 'A-Z'|sed 's/0X//g'`
    TEST=$(( 16#$inputHex2 )) 2> /dev/null 
    if [ $? != 0 ]; then
        FatalUsage "Param 2:$2/$inputHex2 is not hexadecimal."
    fi
    local sumDecimal=`echo "16 i $inputHex1 $inputHex2 + p" | dc`
    local outputHex=`printf '0x%06X' "$((10#$sumDecimal))"`
    eval $__resultvar="'$outputHex'"
}

# Subtract two hexadecimal values of the form result = 0xAAAAAA - 0xBBBBBB
function subHex
{
    local __resultvar=$3
    local inputHex1=`echo $1 | tr 'a-z' 'A-Z'|sed 's/0X//g'`
    TEST=$(( 16#$inputHex1 )) 2> /dev/null 
    if [ $? != 0 ]; then
        FatalUsage "Param 1:$1/$inputHex1 is not hexadecimal."
    fi
    local inputHex2=`echo $2 | tr 'a-z' 'A-Z'|sed 's/0X//g'`
    TEST=$(( 16#$inputHex2 )) 2> /dev/null 
    if [ $? != 0 ]; then
        FatalUsage "Param 2:$2/$inputHex2 is not hexadecimal."
    fi
    local sumDecimal=`echo "16 i $inputHex1 $inputHex2 - p" | dc`
    local outputHex=`printf '0x%06X' "$((10#$sumDecimal))"`
    eval $__resultvar="'$outputHex'"
}


#########################################################################################
# Check enviroment
#########################################################################################

# Correct directory to start.
cd ${BUILDPATH}

# Preload default values into parameter/control variables.
#
DEBUGMODE=0;
TRACEMODE=0;
CPU=EVO;
OS=ZPUTA;
IOCP_VERSION=3;
BRAM_SIZE=0x10000;
getHex 0x01000 OS_BASEADDR;
getHex 0x0C000 APP_BASEADDR;
APP_LEN=0x00000;
APP_BOOTLEN=0x20;                 # Fixed size as this is the jump table to make calls within ZPUTA.
OSVER=2;

# Process parameters, loading up variables as necessary.
#
if [ $# -gt 0 ]; then
    while getopts ":hC:I:O:o:M:B:A:ds:x" opt; do
        case $opt in
            d)     DEBUGMODE=1;;
            C)     CPU=`echo ${OPTARG} | tr 'a-z' 'A-Z'`;;
            I)     IOCP_VERSION=${OPTARG};;
            O)     OS=`echo ${OPTARG} | tr 'a-z' 'A-Z'`;;
            o)     OSVER=${OPTARG};;
            M)     getHex ${OPTARG} BRAM_SIZE;;
            B)     getHex ${OPTARG} OS_BASEADDR;;
            A)     getHex ${OPTARG} APP_BASEADDR;;
            s)     getHex ${OPTARG} APP_LEN;;
            x)     set -x; TRACEMODE=1;;
            h)     Usage;;
           \?)     FatalUsage "Unknown option: -${OPTARG}";;
        esac
    done
    shift $(($OPTIND - 1 ))
fi

# Check the program to build is correct
if [ "${OS}" != "ZPUTA" -a "${OS}" != "ZOS" ]; then
    FatalUsage "Given <os> is not valid, must be 'zputa' or 'zos'"
fi

# Clear out the build target directory.
rm -fr ${BUILDPATH}/build
mkdir -p ${BUILDPATH}/build
mkdir -p ${BUILDPATH}/build/SD

echo "Building: ${OS}, OS_BASEADDR=${OS_BASEADDR}, APP_BASEADDR=${APP_BASEADDR} ..."

# Stack start address (at the moment) is top of BRAM less 8 bytes (2 words), standard for the ZPU. There is
# no reason though why this cant be a fixed address determined by the developer in any memory location.
subHex ${BRAM_SIZE} 8 STACK_STARTADDR

# Setup the bootloader if the OS is not standalone.
#
#if [ "${OSVER}" -ne 0 ]; then

    # Setup variables to meet the required IOCP configuration.
    #
    FUNCTIONALITY=${IOCP_VERSION} 
    if [ ${IOCP_VERSION} = 0 ]; then
        IOCP_BASEADDR=0x000000;
        IOCP_BOOTLEN=0x000400;
        IOCP_STARTADDR=0x000400;
        IOCP_LEN=0x003700;
        OS_SD_TARGET="BOOT.ROM"
    elif [ ${IOCP_VERSION} = 1 ]; then
        IOCP_BASEADDR=0x000000;
        IOCP_BOOTLEN=0x000400;
        IOCP_STARTADDR=0x000400;
        IOCP_LEN=0x002000;
        OS_SD_TARGET="BOOT.ROM"
    elif [ ${IOCP_VERSION} = 2 ]; then
        IOCP_BASEADDR=0x000000;
        IOCP_BOOTLEN=0x000400;
        IOCP_STARTADDR=0x000400;
        IOCP_LEN=0x002000;
        OS_SD_TARGET="BOOT.ROM"
    elif [ ${IOCP_VERSION} = 3 ]; then
        IOCP_BASEADDR=0x000000;
        IOCP_BOOTLEN=0x000400;
        IOCP_STARTADDR=0x000400;
        IOCP_LEN=0x001000;
        OS_SD_TARGET="BOOTTINY.ROM"
    else
        FatalUsage "Illegal IOCP Version."
    fi
    IOCP_SD_TARGET="IOCP_${FUNCTIONALITY}_${IOCP_BASEADDR}.bin"
    addHex ${IOCP_BASEADDR} ${IOCP_LEN} IOCP_APPADDR

    if [ $DEBUGMODE -eq 1 ]; then
        echo "IOCP_BASEADDR=${IOCP_BASEADDR}, IOCP_BOOTLEN=${IOCP_BOOTLEN}, IOCP_STARTADDR=${IOCP_STARTADDR}, IOCP_LEN=${IOCP_LEN}, OS_SD_TARGET=${OS_SD_TARGET}"
    fi

    echo "Building IOCP version - ${IOCP_VERSION}"
    cat ${BUILDPATH}/startup/iocp_bram.tmpl | sed -e "s/BOOTADDR/${IOCP_BASEADDR}/g" -e "s/BOOTLEN/${IOCP_BOOTLEN}/g" -e "s/IOCPSTART/${IOCP_STARTADDR}/g" -e "s/IOCPLEN/${IOCP_LEN}/g" -e "s/STACK_ADDR/${STACK_STARTADDR}/g" > ${BUILDPATH}/startup/iocp_bram_${IOCP_BASEADDR}.ld
    cd ${BUILDPATH}/iocp
    make clean
    echo "make IOCP_BASEADDR=${IOCP_BASEADDR} IOCP_APPADDR=${IOCP_APPADDR} FUNCTIONALITY=${FUNCTIONALITY} CPU=${CPU}"
    make IOCP_BASEADDR=${IOCP_BASEADDR} IOCP_APPADDR=${IOCP_APPADDR} FUNCTIONALITY=${FUNCTIONALITY} CPU=${CPU}
    if [ $? != 0 ]; then
        echo "Aborting, failed to build!"
        exit 1
    fi
    cp ${BUILDPATH}/iocp/iocp.bin ${BUILDPATH}/build/${IOCP_SD_TARGET}
#fi

# Setup variables to meet the required ZPUTA configuration.
# 0 - Standalone, 1 - As app with IOCP Bootloader, 2 - As app with tiny IOCP Bootloader, 3 - As app in RAM 
if [ ${OSVER} = 0 ]; then
    OSBUILDSTR="zputa_standalone_boot_in_bram"
    OS_BOOTADDR=0x000000;
    OS_BASEADDR=0x000000;
    OS_BOOTLEN=0x000600;
elif [ ${OSVER} = 1 ]; then
    OSBUILDSTR="zputa_with_iocp_in_bram"
    OS_BOOTADDR=${OS_BASEADDR};
    OS_BOOTLEN=0x000200;
elif [ ${OSVER} = 2 ]; then
    OSBUILDSTR="zputa_with_tiny_iocp_in_bram"
    OS_BOOTADDR=${OS_BASEADDR};
    OS_BOOTLEN=0x000200;
elif [ ${OSVER} = 3 ]; then
    OSBUILDSTR="zputa_as_app_in_ram"
    OS_BOOTADDR=${OS_BASEADDR};
    OS_BOOTLEN=0x000200;
else
    FatalUsage "Illegal OS Version."
fi 

# Calculate the Start address of the OS. The OS has a Boot Address followed by a reserved space for microcode and hooks before the main OS code.
addHex ${OS_BOOTLEN} ${OS_BASEADDR} OS_STARTADDR

# Calculate the Start address of the Application. An Application has a Boot Address, a reserved space for OS Hooks and then the application start.
addHex ${APP_BOOTLEN} ${APP_BASEADDR} APP_STARTADDR

# Calculate the maximum Application length by subtracting the size of the BRAM - Application Start - Stack Space
if [ "${APP_LEN}" = "" -a $(( 16#`echo ${APP_STARTADDR} | tr 'a-z' 'A-Z'|sed 's/0X//g'` )) -lt  $(( 16#`echo ${BRAM_SIZE} | tr 'a-z' 'A-Z'|sed 's/0X//g'` )) ]; then
    subHex ${BRAM_SIZE} ${APP_STARTADDR} APP_LEN
    subHex ${APP_LEN} 0x20               APP_LEN

# If the APPLEN isnt set, give it a meaningful default.
elif [ $(( 16#`echo ${APP_LEN} | tr 'a-z' 'A-Z'|sed 's/0X//g'` )) -eq 0 ]; then
    APP_LEN=0x10000;
fi

# Calculate the start of the Operating system code as the first section from the boot address is reserved.
addHex ${OS_BOOTADDR} ${OS_BOOTLEN}  OS_STARTADDR

# Calculate the length of the OS which is the start address of the App less the Boot address of the OS.
subHex ${APP_BASEADDR} ${OS_BOOTADDR} OS_LEN
subHex ${OS_LEN} ${OS_BOOTLEN}        OS_LEN

if [ $DEBUGMODE -eq 1 ]; then
    echo "OS_BASEADDR=${OS_BASEADDR}, OS_BOOTLEN=${OS_BOOTLEN}, OS_STARTADDR=${OS_STARTADDR}, OS_LEN=${OS_LEN}"
    echo "APP_BASEADDR=${APP_BASEADDR}, APP_BOOTLEN=${APP_BOOTLEN}, APP_STARTADDR=${APP_STARTADDR}, APP_LEN=${APP_LEN}"
fi

# Build the ZPUTA link script based on given and calculated values.
echo "ZPUTA - ${OSBUILDSTR}"
cat ${BUILDPATH}/startup/zputa.tmpl | sed -e "s/BOOTADDR/${OS_BOOTADDR}/g" -e "s/BOOTLEN/${OS_BOOTLEN}/g" -e "s/OS_START/${OS_STARTADDR}/g" -e "s/OS_LEN/${OS_LEN}/g" -e "s/STACK_ADDR/${STACK_STARTADDR}/g" > ${BUILDPATH}/startup/${OSBUILDSTR}.ld
cd ${BUILDPATH}/zputa
make clean
echo "make ${OSBUILDSTR} ZPUTA_BASEADDR=${OS_BOOTADDR} ZPUTA_APPADDR=${APP_BASEADDR} CPU=${CPU}"
make ${OSBUILDSTR} ZPUTA_BASEADDR=${OS_BOOTADDR} ZPUTA_APPADDR=${APP_BASEADDR} CPU=${CPU}
if [ $? != 0 ]; then
	echo "Aborting, failed to build!"
	exit 1
fi
cp ${BUILDPATH}/zputa/${OSBUILDSTR}.bin ${BUILDPATH}/build/SD/${OS_SD_TARGET}

# Build the apps and install into the build tree.
cat ${BUILDPATH}/startup/app_standalone.tmpl | sed -e "s/BOOTADDR/${APP_BASEADDR}/g" -e "s/BOOTLEN/${APP_BOOTLEN}/g" -e "s/APPSTART/${APP_STARTADDR}/g" -e "s/APPLEN/${APP_LEN}/g" -e "s/STACK_ADDR/${STACK_STARTADDR}/g" > ${BUILDPATH}/startup/app_standalone_${OS_BOOTADDR}_${APP_BASEADDR}.ld
cd ${BUILDPATH}/apps
make clean
echo "make ZPUTA_BASEADDR=${OS_BOOTADDR} ZPUTA_APPADDR=${APP_BASEADDR} CPU=${CPU}"
make ZPUTA_BASEADDR=${OS_BOOTADDR} ZPUTA_APPADDR=${APP_BASEADDR} CPU=${CPU}
if [ $? != 0 ]; then
	echo "Aborting, failed to build!"
	exit 1
fi
mkdir -p bin
rm -f bin/*
make install
cp -r ${BUILDPATH}/apps/bin ${BUILDPATH}/build/SD/bin
