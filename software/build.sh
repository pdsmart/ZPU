#!/bin/bash
#========================================================================================================
# NAME
#     build.sh -  Shell script to build a ZPU program or OS.
#
# SYNOPSIS
#     build.sh [-dOBAh]
#
# DESCRIPTION
#
# OPTIONS
#     -I <iocp ver> = 0 - Full, 1 - Medium, 2 - Minimum, 3 - Tiny (bootstrap only)
#     -O <os>       = zputa, zos
#     -o <os ver>   = 0 - Standalone, 1 - As app with IOCP Bootloader,
#                     2 - As app with tiny IOCP Bootloader, 3 - As app in RAM 
#     -B <addr>     = Base address of <os>, default 0x01000
#     -A <addr>     = App address of <os>, default 0x0C000
#     -d            = Debug mode.
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
#========================================================================================================

PROG=${0##*/}
#PARAMS="`basename ${PROG} '.sh'`.params"
ARGS=$*

##############################################################################
# Load program specific variables
##############################################################################

# VERSION of this RELEASE.
#
VERSION="1.00"

# Constants.
BUILDPATH=/dvlp/Projects/dev/github/zpu/software

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

# Add two hexadecimal values of the form 0xAAAAAA + 0xBBBBBB
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


#########################################################################################
# Check enviroment
#########################################################################################

# Correct directory to start.
cd ${BUILDPATH}

# Preload default values into parameter/control variables.
#
DEBUGMODE=0;
OS=ZPUTA;
IOCP_VERSION=3
getHex 0x01000 OS_BASEADDR;
getHex 0x0C000 OS_APPADDR;
getHex 0x03700 OS_APPLEN;
OSVER=2;

# Process parameters, loading up variables as necessary.
#
if [ $# -gt 0 ]; then
    NOOPT=1
    while getopts ":hI:O:o:B:A:s:" opt; do
        NOOPT=0
        case $opt in
            d)     DEBUGMODE=1;;
            I)     IOCP_VERSION=${OPTARG};;
            O)     OS=${OPTARG};;
            o)     OSVER=${OPTARG};;
            B)     getHex ${OPTARG} OS_BASEADDR;;
            A)     getHex ${OPTARG} OS_APPADDR;;
            s)     getHex ${OPTARG} OS_APPLEN;;
            h)     Usage;;
           \?)     Usage;;
        esac
    done
    if [ ${NOOPT} = 1 ]; then
        FatalUsage "Unknown option: $1"
    fi
    shift $(($OPTIND - 1 ))
fi

OS=`echo ${OS} | tr 'a-z' 'A-Z'` 
OS_BOOTADDR=${OS_APPADDR}
OS_BOOTLEN=0x000100
addHex ${OS_BOOTLEN} ${OS_APPADDR} OS_APPSTART
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

if [ ${OSVER} = 0 ]; then
    OSBUILDSTR="zputa_standalone_boot"
elif [ ${OSVER} = 1 ]; then
    OSBUILDSTR="zputa_with_iocp_in_bram"
elif [ ${OSVER} = 2 ]; then
    OSBUILDSTR="zputa_with_tiny_iocp_in_bram"
elif [ ${OSVER} = 3 ]; then
    OSBUILDSTR="zputa_as_app_in_ram"
else
    FatalUsage "Illegal OS Version."
fi 

# Check the program to build is correct
if [ "${OS}" != "ZPUTA" -a "${OS}" != "ZOS" ]; then
    FatalUsage "Given <os> is not valid, must be 'zputa' or 'zos'"
fi

echo "Building: ${OS}, OS_BASEADDR=${OS_BASEADDR}, OS_APPADDR=${OS_APPADDR}, OS_APPLEN=${OS_APPLEN}, ..."


# Clear out the build target directory.
rm -fr ${BUILDPATH}/build
mkdir -p ${BUILDPATH}/build
mkdir -p ${BUILDPATH}/build/SD

echo "IOCP - ${IOCP_VERSION}"
cat ${BUILDPATH}/startup/iocp_bram.tmpl | sed -e "s/BOOTADDR/${IOCP_BASEADDR}/g" -e "s/BOOTLEN/${IOCP_BOOTLEN}/g" -e "s/IOCPSTART/${IOCP_STARTADDR}/g" -e "s/IOCPLEN/${IOCP_LEN}/g" > ${BUILDPATH}/startup/iocp_bram_${IOCP_BASEADDR}.ld
cd ${BUILDPATH}/iocp
make clean
echo "make IOCP_BASEADDR=${IOCP_BASEADDR} IOCP_APPADDR=${IOCP_APPADDR} FUNCTIONALITY=${FUNCTIONALITY}"
make IOCP_BASEADDR=${IOCP_BASEADDR} IOCP_APPADDR=${IOCP_APPADDR} FUNCTIONALITY=${FUNCTIONALITY}
if [ $? != 0 ]; then
	echo "Aborting, failed to build!"
	exit 1
fi
cp ${BUILDPATH}/iocp/iocp.bin ${BUILDPATH}/build/${IOCP_SD_TARGET}

echo "ZPUTA - ${OSBUILDSTR}"
cd ${BUILDPATH}/zputa
make clean
echo "make ${OSBUILDSTR} ZPUTA_BASEADDR=${OS_BASEADDR} ZPUTA_APPADDR=${OS_APPADDR}"
make ${OSBUILDSTR} ZPUTA_BASEADDR=${OS_BASEADDR} ZPUTA_APPADDR=${OS_APPADDR}
if [ $? != 0 ]; then
	echo "Aborting, failed to build!"
	exit 1
fi
cp ${BUILDPATH}/zputa/${OSBUILDSTR}.bin ${BUILDPATH}/build/SD/${OS_SD_TARGET}

# Build the apps and install into the build tree.
cat ${BUILDPATH}/startup/app_standalone.tmpl | sed -e "s/BOOTADDR/${OS_BOOTADDR}/g" -e "s/BOOTLEN/${OS_BOOTLEN}/g" -e "s/APPSTART/${OS_APPSTART}/g" -e "s/APPLEN/${OS_APPLEN}/g" > ${BUILDPATH}/startup/app_standalone_${OS_BASEADDR}_${OS_APPADDR}.ld
cd ${BUILDPATH}/apps
make clean
make ZPUTA_BASEADDR=${OS_BASEADDR} ZPUTA_APPADDR=${OS_APPADDR}
if [ $? != 0 ]; then
	echo "Aborting, failed to build!"
	exit 1
fi
mkdir -p bin
rm -f bin/*
make install
cp -r ${BUILDPATH}/apps/bin ${BUILDPATH}/build/SD/bin
