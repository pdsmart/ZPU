////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Name:            tools.h
// Created:         January 2019
// Author(s):       Philip Smart
// Description:     ZPUTA application tools.
//                  A set of tools to be used by the ZPUTA application.
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
#ifndef TOOLS_H
#define TOOLS_H

#ifdef __cplusplus
extern "C" {
#endif

// Constants.
#define CMD_DISK_DUMP               1              // Disk Commands Range 01 .. 09
#define CMD_DISK_INIT               2
#define CMD_DISK_STATUS             3 
#define CMD_DISK_IOCTL_SYNC         4
#define CMD_BUFFER_DUMP            10              // Buffer Commands Range 10 .. 19
#define CMD_BUFFER_EDIT            11
#define CMD_BUFFER_READ            12
#define CMD_BUFFER_WRITE           13
#define CMD_BUFFER_FILL            14
#define CMD_BUFFER_LEN             15
#define CMD_FS_INIT                20              // FS Commands Range 20 .. 59
#define CMD_FS_STATUS              21
#define CMD_FS_DIRLIST             22 
#define CMD_FS_OPEN                23
#define CMD_FS_CLOSE               24
#define CMD_FS_SEEK                25
#define CMD_FS_READ                26
#define CMD_FS_CAT                 27
#define CMD_FS_INSPECT             28
#define CMD_FS_WRITE               29
#define CMD_FS_TRUNC               30
#define CMD_FS_RENAME              31
#define CMD_FS_DELETE              32
#define CMD_FS_CREATEDIR           33
#define CMD_FS_ALLOCBLOCK          34
#define CMD_FS_CHANGEATTRIB        35
#define CMD_FS_CHANGETIME          36
#define CMD_FS_COPY                37
#define CMD_FS_CHANGEDIR           38
#define CMD_FS_CHANGEDRIVE         39
#define CMD_FS_SHOWDIR             40
#define CMD_FS_SETLABEL            41
#define CMD_FS_CREATEFS            42
#define CMD_FS_LOAD                43
#define CMD_FS_DUMP                44
#define CMD_FS_CONCAT              45
#define CMD_FS_XTRACT              46
#define CMD_FS_SAVE                47
#define CMD_FS_EXEC                48
#define CMD_MEM_CLEAR              60              // MEM Commands Range 60 .. 79
#define CMD_MEM_COPY               61              
#define CMD_MEM_DIFF               63
#define CMD_MEM_DUMP               64
#define CMD_MEM_EDIT_BYTES         65
#define CMD_MEM_EDIT_HWORD         66
#define CMD_MEM_EDIT_WORD          67
#define CMD_MEM_TEST               68
#define CMD_HW_INTR_DISABLE        80              // HW Commands Range 80 .. 99
#define CMD_HW_INTR_ENABLE         81
#define CMD_HW_SHOW_REGISTER       82
#define CMD_HW_TEST_TIMERS         83
#define CMD_HW_FIFO_DISABLE        84
#define CMD_HW_FIFO_ENABLE         85
#define CMD_TEST_DHRYSTONE        100              // TEST Commands Range 100 .. 119
#define CMD_TEST_COREMARK         101
#define CMD_EXECUTE               120              // EXECUTE Commands Range 120 .. 129
#define CMD_CALL                  121
#define CMD_MISC_RESTART_APP      130              // MISC Commands Range 130 ..149 
#define CMD_MISC_REBOOT           131
#define CMD_MISC_HELP             132
#define CMD_MISC_INFO             133
#define CMD_MISC_SETTIME          134
#define CMD_MISC_TEST             135
#define CMD_BADKEY                 -1
#define CMD_NOKEY                   0 
#define CMD_GROUP_DISK              1
#define CMD_GROUP_BUFFER            2
#define CMD_GROUP_FS                3
#define CMD_GROUP_MEM               4
#define CMD_GROUP_HW                5
#define CMD_GROUP_TEST              6
#define CMD_GROUP_EXEC              7
#define CMD_GROUP_MISC              8
#define CMD_GROUP_DISK_NAME         "DISK IO CONTROLS"
#define CMD_GROUP_BUFFER_NAME       "DISK BUFFER CONTROLS"
#define CMD_GROUP_FS_NAME           "FILESYSTEM CONTROLS"
#define CMD_GROUP_MEM_NAME          "MEMORY"
#define CMD_GROUP_HW_NAME           "HARDWARE"
#define CMD_GROUP_TEST_NAME         "TESTING"
#define CMD_GROUP_EXEC_NAME         "EXECUTION"
#define CMD_GROUP_MISC_NAME         "MISC COMMANDS"
 
// File Execution modes.
//
#define EXEC_MODE_CALL              0
#define EXEC_MODE_JMP               1

// Size of sector buffer.
//
#define SECTOR_SIZE                 512

// Command list.
//
typedef struct {
    char     *cmd;
    uint8_t  builtin;
    uint8_t  key;
    uint8_t  group;
    char     *params;
    char     *description;
} t_cmdstruct;

// Group id to names.
//
typedef struct {
    uint8_t  key;
    char     *name;
} t_groupstruct;

// Help text mapped to associated command.
typedef struct {
    uint8_t  key;
    char     *params;
    char     *description;
} t_helpstruct;

#if defined(ZPUTA) || (defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1)
// Table of groups and associated group id, used to index the cmd table.
static t_groupstruct groupTable[] = {
    { CMD_GROUP_DISK,    CMD_GROUP_DISK_NAME }, 
    { CMD_GROUP_BUFFER,  CMD_GROUP_BUFFER_NAME }, 
    { CMD_GROUP_FS,      CMD_GROUP_FS_NAME }, 
    { CMD_GROUP_MEM,     CMD_GROUP_MEM_NAME }, 
    { CMD_GROUP_HW,      CMD_GROUP_HW_NAME }, 
    { CMD_GROUP_TEST,    CMD_GROUP_TEST_NAME }, 
    { CMD_GROUP_EXEC,    CMD_GROUP_EXEC_NAME }, 
    { CMD_GROUP_MISC,    CMD_GROUP_MISC_NAME }, 
};

// Table of supported commands. The table contains the command, group to which it belongs, parameters needed (for display)
// and help text.
static t_cmdstruct cmdTable[] = {
  // Full command names.
  #if defined(USE_SDCARD)
    // Disk level commands.
    #if (defined(BUILTIN_DISK_DUMP) && BUILTIN_DISK_DUMP == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "ddump",      BUILTIN_DISK_DUMP,        CMD_DISK_DUMP,        CMD_GROUP_DISK },
    #endif
    { "dinit",      BUILTIN_DEFAULT,          CMD_DISK_INIT,        CMD_GROUP_DISK },
    #if (defined(BUILTIN_DISK_STATUS) && BUILTIN_DISK_STATUS == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "dstat",      BUILTIN_DISK_STATUS,      CMD_DISK_STATUS,      CMD_GROUP_DISK },
    #endif
    { "dioctl",     BUILTIN_DEFAULT,          CMD_DISK_IOCTL_SYNC,  CMD_GROUP_DISK },
    // Disk buffer level commands.
    #if (defined(BUILTIN_BUFFER_DUMP) && BUILTIN_BUFFER_DUMP == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "bdump",      BUILTIN_BUFFER_DUMP,      CMD_BUFFER_DUMP,      CMD_GROUP_BUFFER },
    #endif
    #if (defined(BUILTIN_BUFFER_EDIT) && BUILTIN_BUFFER_EDIT == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "bedit",      BUILTIN_BUFFER_EDIT,      CMD_BUFFER_EDIT,      CMD_GROUP_BUFFER },
    #endif
    #if (defined(BUILTIN_BUFFER_READ) && BUILTIN_BUFFER_READ == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "bread",      BUILTIN_BUFFER_READ,      CMD_BUFFER_READ,      CMD_GROUP_BUFFER },
    #endif
    #if (defined(BUILTIN_BUFFER_WRITE) && BUILTIN_BUFFER_WRITE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "bwrite",     BUILTIN_BUFFER_WRITE,     CMD_BUFFER_WRITE,     CMD_GROUP_BUFFER },
    #endif
    #if (defined(BUILTIN_BUFFER_FILL) && BUILTIN_BUFFER_FILL == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "bfill",      BUILTIN_BUFFER_FILL,      CMD_BUFFER_FILL,      CMD_GROUP_BUFFER },
    #endif
    #if (defined(BUILTIN_BUFFER_LEN) && BUILTIN_BUFFER_LEN == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "blen",       BUILTIN_BUFFER_LEN,       CMD_BUFFER_LEN,       CMD_GROUP_BUFFER },
    #endif
    // Filesystem level commands.
    //   File contents manipulation commands.
    { "finit",      BUILTIN_DEFAULT,          CMD_FS_INIT,          CMD_GROUP_FS },
    #if (defined(BUILTIN_FS_OPEN) && BUILTIN_FS_OPEN == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fopen",      BUILTIN_FS_OPEN,          CMD_FS_OPEN,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_CLOSE) && BUILTIN_FS_CLOSE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fclose",     BUILTIN_FS_CLOSE,         CMD_FS_CLOSE,         CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_SEEK) && BUILTIN_FS_SEEK == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fseek",      BUILTIN_FS_SEEK,          CMD_FS_SEEK,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_READ) && BUILTIN_FS_READ == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fread",      BUILTIN_FS_READ,          CMD_FS_READ,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_INSPECT) && BUILTIN_FS_INSPECT == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "finspect",   BUILTIN_FS_INSPECT,       CMD_FS_INSPECT,       CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_WRITE) && BUILTIN_FS_WRITE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fwrite",     BUILTIN_FS_WRITE,         CMD_FS_WRITE,         CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_TRUNC) && BUILTIN_FS_TRUNC == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "ftrunc",     BUILTIN_FS_TRUNC,         CMD_FS_TRUNC,         CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_ALLOCBLOCK) && BUILTIN_FS_ALLOCBLOCK == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "falloc",     BUILTIN_FS_ALLOCBLOCK,    CMD_FS_ALLOCBLOCK,    CMD_GROUP_FS },
    #endif
    //   File commands.
    #if (defined(BUILTIN_FS_CHANGEATTRIB) && BUILTIN_FS_CHANGEATTRIB == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fattr",      BUILTIN_FS_CHANGEATTRIB,  CMD_FS_CHANGEATTRIB,  CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_CHANGETIME) && BUILTIN_FS_CHANGETIME == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "ftime",      BUILTIN_FS_CHANGETIME,    CMD_FS_CHANGETIME,    CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_RENAME) && BUILTIN_FS_RENAME == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "frename",    BUILTIN_FS_RENAME,        CMD_FS_RENAME,        CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_DELETE) && BUILTIN_FS_DELETE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fdel",       BUILTIN_FS_DELETE,        CMD_FS_DELETE,        CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_CREATEDIR) && BUILTIN_FS_CREATEDIR == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fmkdir",     BUILTIN_FS_CREATEDIR,     CMD_FS_CREATEDIR,     CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_STATUS) && BUILTIN_FS_STATUS == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fstat",      BUILTIN_FS_STATUS,        CMD_FS_STATUS,        CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_DIRLIST) && BUILTIN_FS_DIRLIST == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fdir",       BUILTIN_FS_DIRLIST,       CMD_FS_DIRLIST,       CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_CAT) && BUILTIN_FS_CAT == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fcat",       BUILTIN_FS_CAT,           CMD_FS_CAT,           CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_COPY) && BUILTIN_FS_COPY == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fcp",        BUILTIN_FS_COPY,          CMD_FS_COPY,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_CONCAT) && BUILTIN_FS_CONCAT == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fconcat",    BUILTIN_FS_CONCAT,        CMD_FS_CONCAT,        CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_XTRACT) && BUILTIN_FS_XTRACT == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fxtract",    BUILTIN_FS_XTRACT,        CMD_FS_XTRACT,        CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_LOAD) && BUILTIN_FS_LOAD == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fload",      BUILTIN_FS_LOAD,          CMD_FS_LOAD,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_EXEC) && BUILTIN_FS_EXEC == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fexec",      BUILTIN_FS_EXEC,          CMD_FS_EXEC,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_SAVE) && BUILTIN_FS_SAVE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fsave",      BUILTIN_FS_SAVE,          CMD_FS_SAVE,          CMD_GROUP_FS },
    #endif
    #if (defined(BUILTIN_FS_DUMP) && BUILTIN_FS_DUMP == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fdump",      BUILTIN_FS_DUMP,          CMD_FS_DUMP,          CMD_GROUP_FS },
    #endif
   #if FF_FS_RPATH
    #if (defined(BUILTIN_FS_CHANGEDIR) && BUILTIN_FS_CHANGEDIR == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fcd",        BUILTIN_FS_CHANGEDIR,     CMD_FS_CHANGEDIR,     CMD_GROUP_FS },
    #endif
    #if FF_VOLUMES >= 2
    #if (defined(BUILTIN_FS_CHANGEDRIVE) && BUILTIN_FS_CHANGEDRIVE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fdrive",     BUILTIN_FS_CHANGEDRIVE,   CMD_FS_CHANGEDRIVE,   CMD_GROUP_FS },
    #endif
    #endif
    #if FF_FS_RPATH >= 2
    #if (defined(BUILTIN_FS_SHOWDIR) && BUILTIN_FS_SHOWDIR == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fshowdir",   BUILTIN_FS_SHOWDIR,       CMD_FS_SHOWDIR,       CMD_GROUP_FS },
    #endif
    #endif
   #endif
   #if FF_USE_LABEL
    #if (defined(BUILTIN_FS_SETLABEL) && BUILTIN_FS_SETLABEL == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "flabel",     BUILTIN_FS_SETLABEL,      CMD_FS_SETLABEL,      CMD_GROUP_FS },
    #endif
   #endif
   #if FF_USE_MKFS
    #if (defined(BUILTIN_FS_CREATEFS) && BUILTIN_FS_CREATEFS == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "fmkfs",      BUILTIN_FS_CREATEFS,      CMD_FS_CREATEFS,      CMD_GROUP_FS },
    #endif
   #endif
  #endif
    // Memory commands.
    #if (defined(BUILTIN_MEM_CLEAR) && BUILTIN_MEM_CLEAR == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "mclear",     BUILTIN_MEM_CLEAR,        CMD_MEM_CLEAR,        CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_COPY) && BUILTIN_MEM_COPY == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "mcopy",      BUILTIN_MEM_COPY,         CMD_MEM_COPY,         CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_DIFF) && BUILTIN_MEM_DIFF == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "mdiff",      BUILTIN_MEM_DIFF,         CMD_MEM_DIFF,         CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_DUMP) && BUILTIN_MEM_DUMP == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "mdump",      BUILTIN_MEM_DUMP,         CMD_MEM_DUMP,         CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_TEST) && BUILTIN_MEM_TEST == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "mtest",      BUILTIN_MEM_TEST,         CMD_MEM_TEST,         CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_EDIT_BYTES) && BUILTIN_MEM_EDIT_BYTES == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "meb",        BUILTIN_MEM_EDIT_BYTES,   CMD_MEM_EDIT_BYTES,   CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_EDIT_HWORD) && BUILTIN_MEM_EDIT_HWORD == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "meh",        BUILTIN_MEM_EDIT_HWORD,   CMD_MEM_EDIT_HWORD,   CMD_GROUP_MEM },
    #endif
    #if (defined(BUILTIN_MEM_EDIT_WORD) && BUILTIN_MEM_EDIT_WORD == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "mew",        BUILTIN_MEM_EDIT_WORD,    CMD_MEM_EDIT_WORD,    CMD_GROUP_MEM },
    #endif
    // Hardware commands.
    { "hid",        BUILTIN_DEFAULT,          CMD_HW_INTR_DISABLE,  CMD_GROUP_HW },
    { "hie",        BUILTIN_DEFAULT,          CMD_HW_INTR_ENABLE,   CMD_GROUP_HW },
    #if (defined(BUILTIN_HW_SHOW_REGISTER) && BUILTIN_HW_SHOW_REGISTER == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "hr",         BUILTIN_HW_SHOW_REGISTER, CMD_HW_SHOW_REGISTER, CMD_GROUP_HW },
    #endif
    #if (defined(BUILTIN_HW_TEST_TIMERS) && BUILTIN_HW_TEST_TIMERS == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "ht",         BUILTIN_HW_TEST_TIMERS,   CMD_HW_TEST_TIMERS,   CMD_GROUP_HW },
    #endif
    { "hfd",        BUILTIN_DEFAULT,          CMD_HW_FIFO_DISABLE,  CMD_GROUP_HW },
    { "hfe",        BUILTIN_DEFAULT,          CMD_HW_FIFO_ENABLE,   CMD_GROUP_HW },
    // Test suite commands.
    #if (defined(BUILTIN_TST_DHRYSTONE) && BUILTIN_TST_DHRYSTONE == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "dhry",       BUILTIN_TST_DHRYSTONE,    CMD_TEST_DHRYSTONE,   CMD_GROUP_TEST },
    #endif
    #if (defined(BUILTIN_TST_COREMARK) && BUILTIN_TST_COREMARK == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "coremark",   BUILTIN_TST_COREMARK,     CMD_TEST_COREMARK,    CMD_GROUP_TEST },
    #endif
    // Execution commands.
    { "call",       BUILTIN_DEFAULT,          CMD_CALL,             CMD_GROUP_EXEC },
    { "jmp",        BUILTIN_DEFAULT,          CMD_EXECUTE,          CMD_GROUP_EXEC },
    // Miscellaneous commands.
    { "restart",    BUILTIN_DEFAULT,          CMD_MISC_RESTART_APP, CMD_GROUP_MISC },
    { "reset",      BUILTIN_DEFAULT,          CMD_MISC_REBOOT,      CMD_GROUP_MISC },
    #if defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1
    { "help",       BUILTIN_MISC_HELP,        CMD_MISC_HELP,        CMD_GROUP_MISC },
    #endif
    { "info",       BUILTIN_DEFAULT,          CMD_MISC_INFO,        CMD_GROUP_MISC },
    #if (defined(BUILTIN_MISC_SETTIME) && BUILTIN_MISC_SETTIME == 1) || (defined(BUILTIN_MISC_HELP) == 1 && BUILTIN_MISC_HELP == 1)
    { "time",       BUILTIN_MISC_SETTIME,     CMD_MISC_SETTIME,     CMD_GROUP_MISC },
    #endif
    { "test",       BUILTIN_DEFAULT,          CMD_MISC_TEST,        CMD_GROUP_MISC },
};
#endif

// Table of text to describe a command and its associated parameters. This table maps to the cmdTable with the Command as the key.
//
#if (defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1)
static t_helpstruct helpTable[] = {
  #if defined(USE_SDCARD)
    // Disk level commands.
    { CMD_DISK_DUMP,        "[<pd#> <sect>]",                   "Dump a sector" },
    { CMD_DISK_INIT,        "<pd#> [<card type>]",              "Initialize disk" },
    { CMD_DISK_STATUS,      "<pd#>",                            "Show disk status" },
    { CMD_DISK_IOCTL_SYNC,  "<pd#>",                            "ioctl(CTRL_SYNC)" },
    // Disk buffer level commands.
    { CMD_BUFFER_DUMP,      "<ofs>",                            "Dump buffer" }, 
    { CMD_BUFFER_EDIT,      "<ofs> [<data>] ...",               "Edit buffer" },
    { CMD_BUFFER_READ,      "<pd#> <sect> [<num>]",             "Read into buffer" },
    { CMD_BUFFER_WRITE,     "<pd#> <sect> [<num>]",             "Write buffer to disk" },
    { CMD_BUFFER_FILL,      "<val>",                            "Fill buffer" },
    { CMD_BUFFER_LEN,       "<len>",                            "Set read/write length for fr/fw command" },
    // Filesystem level commands.
    //   File contents manipulation commands.
    { CMD_FS_INIT,          "<ld#> [<mount>]",                  "Force init the volume" },
    { CMD_FS_OPEN,          "<mode> <file>",                    "Open a file" },
    { CMD_FS_CLOSE,         "",                                 "Close the file" },
    { CMD_FS_SEEK,          "<ofs>",                            "Move fp in normal seek" },
    { CMD_FS_READ,          "<len>",                            "Read part of file into buffer" },
    { CMD_FS_INSPECT,       "<len>",                            "Read part of file and examine" },
    { CMD_FS_WRITE,         "<len> <val>",                      "Write part of buffer into file" },
    { CMD_FS_TRUNC,         "",                                 "Truncate the file at current fp" },
    { CMD_FS_ALLOCBLOCK,    "<fsz> <opt>",                      "Allocate ctg blks to file" },
    //   File commands.
    { CMD_FS_CHANGEATTRIB,  "<atrr> <mask> <name>",             "Change object attribute" },
    { CMD_FS_CHANGETIME,    "<y> <m> <d> <h> <M> <s> <fn>",     "Change object timestamp" },
    { CMD_FS_RENAME,        "<org name> <new name>",            "Rename an object" },
    { CMD_FS_DELETE,        "<obj name>",                       "Delete an object" },
    { CMD_FS_CREATEDIR,     "<dir name>",                       "Create a directory" },
    { CMD_FS_STATUS,        "[<path>]",                         "Show volume status" },
    { CMD_FS_DIRLIST,       "[<path>]",                         "Show a directory" }, 
    { CMD_FS_CAT,           "<name>",                           "Output file contents" },
    { CMD_FS_COPY,          "<src file> <dst file>",            "Copy a file" },
    { CMD_FS_CONCAT,        "<src fn1> < src fn2> <dst fn>",    "Concatenate 2 files" },
    { CMD_FS_XTRACT,        "<src> <dst> <start pos> <len>",    "Extract a portion of file" },
    { CMD_FS_LOAD,          "<name> [<addr>]",                  "Load a file into memory" },
    { CMD_FS_EXEC,          "<name> <ldAddr> <xAddr> <mode>",   "Load and execute file" },
    { CMD_FS_SAVE,          "<name> <addr> <len>",              "Save memory range to a file" },
    { CMD_FS_DUMP,          "<name> [<width>]",                 "Dump a file contents as hex" },
   #if FF_FS_RPATH
    { CMD_FS_CHANGEDIR,     "<path>",                           "Change current directory" },
    #if FF_VOLUMES >= 2
    { CMD_FS_CHANGEDRIVE,   "<path>",                           "Change current drive" },
    #endif
    #if FF_FS_RPATH >= 2
    { CMD_FS_SHOWDIR,       "",                                 "Show current directory" },
    #endif
   #endif
   #if FF_USE_LABEL
    { CMD_FS_SETLABEL,      "<label>",                          "Set volume label" },
   #endif
   #if FF_USE_MKFS
    { CMD_FS_CREATEFS,      "<ld#> <type> <au>",                "Create FAT volume" },
   #endif
  #endif
    // Memory commands.
    { CMD_MEM_CLEAR,        "<start> <end> [<word>]",           "Clear memory" },
    { CMD_MEM_COPY,         "<start> <end> <dst addr>",         "Copy memory" },
    { CMD_MEM_DIFF,         "<start> <end> <cmp addr>",         "Compare memory" },
    { CMD_MEM_DUMP,         "[<start> [<end>] [<size>]]",       "Dump memory" },
    { CMD_MEM_EDIT_BYTES,   "<addr> <byte> [...]",              "Edit memory (Bytes)" },
    { CMD_MEM_EDIT_HWORD,   "<addr> <h-word> [...]",            "Edit memory (H-Word)" },
    { CMD_MEM_EDIT_WORD,    "<addr> <word> [...]",              "Edit memory (Word)" },
    { CMD_MEM_TEST,         "[<start> [<end>] [iter]",          "Test memory" },
    // Hardware commands.
    { CMD_HW_INTR_DISABLE,  "",                                 "Disable Interrupts" },
    { CMD_HW_INTR_ENABLE,   "",                                 "Enable Interrupts" },
    { CMD_HW_SHOW_REGISTER, "",                                 "Display Register Information" },
    { CMD_HW_TEST_TIMERS,   "",                                 "Test uS Timer" },
    { CMD_HW_FIFO_DISABLE,  "",                                 "Disable UART FIFO" },
    { CMD_HW_FIFO_ENABLE,   "",                                 "Enable UART FIFO" },
    // Test suite commands.
    { CMD_TEST_DHRYSTONE,   "",                                 "Dhrystone Test v2.1" },
    { CMD_TEST_COREMARK,    "",                                 "CoreMark Test v1.0" },
    // Execution commands.
    { CMD_CALL,             "<addr>",                           "Call function @ <addr>" },
    { CMD_EXECUTE,          "<addr>",                           "Execute code @ <addr>" },
    // Miscellaneous commands.
    { CMD_MISC_RESTART_APP, "",                                 "Restart application" },
    { CMD_MISC_REBOOT,      "",                                 "Reset system" },
    { CMD_MISC_HELP,        "[<cmd %>|<group %>]",              "Show this screen" },
    { CMD_MISC_INFO,        "",                                 "Config info" },
    { CMD_MISC_SETTIME,     "[<y> <m> <d> <h> <M> <s>]",        "Set/Show current time" },
    { CMD_MISC_TEST,        "",                                 "Test Screen" },
};
#endif
#define NGRPKEYS (sizeof(groupTable)/sizeof(t_groupstruct))
#define NCMDKEYS (sizeof(cmdTable)/sizeof(t_cmdstruct))
#define NHELPKEYS (sizeof(helpTable)/sizeof(t_helpstruct))

// Prototypes
#if defined(USE_SDCARD)
static FRESULT scan_files(char *);
void          printFSCode(FRESULT);
void          printBytesPerSec(uint32_t, uint32_t, char *);
FRESULT       printDirectoryListing(char *);
FRESULT       printFatFSStatus(char *);
FRESULT       fileConcatenate(char *, char *, char *);
FRESULT       fileCopy(char *, char *);
FRESULT       fileXtract(char *, char *, uint32_t, uint32_t);
FRESULT       fileCat(char *);
FRESULT       fileLoad(char *, uint32_t, uint8_t);
FRESULT       fileSave(char *, uint32_t, uint32_t);
FRESULT       fileDump(char *, uint32_t);
uint32_t      fileExec(char *, uint32_t, uint32_t, uint8_t, uint32_t, uint32_t, uint32_t, uint32_t);
FRESULT       fileBlockRead(FIL *, uint32_t);
FRESULT       fileBlockWrite(FIL *fp, uint32_t len);
FRESULT       fileBlockDump(uint32_t, uint32_t);
FRESULT       fileSetBlockLen(uint32_t);
#endif
#if defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1
void displayHelp(char *);
#endif
#if defined(ZPUTA) || (defined(BUILTIN_MISC_HELP) && BUILTIN_MISC_HELP == 1)
void printVersion(uint8_t);
#endif
#if (defined(BUILTIN_FS_DUMP) && BUILTIN_FS_DUMP == 1) || (defined(BUILTIN_FS_INSPECT) && BUILTIN_FS_INSPECT == 1) || (defined(BUILTIN_DISK_DUMP) && BUILTIN_DISK_DUMP == 1) || (defined(BUILTIN_DISK_STATUS) && BUILTIN_DISK_STATUS == 1) || (defined(BUILTIN_BUFFER_DUMP) && BUILTIN_BUFFER_DUMP == 1) || (defined(BUILTIN_MEM_DUMP) && BUILTIN_MEM_DUMP == 1)
int           memoryDump(uint32_t, uint32_t, uint32_t, uint32_t, uint8_t);
#endif

#ifdef __cplusplus
}
#endif

#endif
