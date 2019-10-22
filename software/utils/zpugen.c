// zpugen.c
//
// Program to turn a binary file into a VHDL lookup table.
//   by Adam Pierce
//   29-Feb-2008
//   Modifier by: Philip Smart, January 2019 to work with the ZPU EVO and its byte addressing modes.
//
// This software is free to use by anyone for any purpose.
//

#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>

typedef unsigned char BYTE;

int writeByteMatrix(int fd, int bytenum, int addr)
{
    BYTE    opcode[4];
    ssize_t s;

    // Set binary input file to beginning.
    if(lseek(fd, 0L, SEEK_SET) != 0)
    {
        perror("Failed to rewind binary file to beginning, os error.");
        return 3;
    }
   
    while(1)
    {
        // Read 32 bits.
        s = read(fd, opcode, 4);
        if(s == -1)
        {
            perror("File read");
            return 3;
        }

        if(s == 0)
            break; // End of file.

        // Output to STDOUT.
        if(bytenum == 4)
        {
            printf("        %6d => x\"%02x%02x%02x%02x\",\n", addr++, opcode[0], opcode[1], opcode[2], opcode[3]);
        } else
        {
            printf("        %6d => x\"%02x\",\n", addr++, opcode[bytenum]);
        }
    }
}

int main(int argc, char **argv)
{
    BYTE    opcode[4];
    int     fd1;
    int     fd2;
    FILE    *tmplfp;
    int     addr1 = 0;
    int     addr2 = 0;
    int     bytenum;
    int     mode = 0;
    char    line[512];
    ssize_t s;

    // Check the user has given us an input file.
    if(argc < 3)
    {
        printf("Usage: %s <0-3 = byte or 4 = 32bit word> <binary_file> [<startaddr>]\n", argv[0]);
        printf("       or\n");
        printf("       %s BA <binary_file> <tmplfile> [<startaddr>]\n\n", argv[0]);
        printf("       or\n");
        printf("       %s BC <binary_file1> <start addr1> <binary_file2> <start addr2> <tmplfile>\n\n", argv[0]);
        return 1;
    }
 
    // Are we generating a Byte Addressed file?
    if(strcmp(argv[1], "BA") == 0)
    {
        mode = 1;
    } else 
    if(strcmp(argv[1], "BC") == 0)
    {
        mode = 2;
    }

    // If optional address start parameter given, set address to its value.
    //
    if((mode == 0 && argc == 4) || (mode == 1 && argc == 5))
    {
        addr1 = atoi(argv[mode == 0 ? 3 : 4]);
    } else
    if(mode == 2)
    {
        addr1 = atoi(argv[3]);
        addr2 = atoi(argv[5]);
    }

    if(mode == 0)
    {
        bytenum = atoi(argv[1]);
        if(bytenum < 0 || bytenum > 4)
        {
            perror("Illegal byte number");
            return 2;
        }
    } else
    {
        // Open the template file.
        tmplfp = fopen(argv[mode == 1 ? 3 : 6], "r");
        if(tmplfp == NULL)
        {
            perror("Template File Open");
            return 2;
        }
    }

    // Open the binary file whose data we need to represent in ascii.
    fd1 = open(argv[2], 0);
    if(fd1 == -1)
    {
        perror("Binary File Open");
        return 2;
    }

    if(mode == 2)
    {
        // Open the application binary file whose data we need to append to the first file in ascii.
        fd2 = open(argv[4], 0);
        if(fd2 == -1)
        {
            perror("Application Binary File Open");
            return 2;
        }
    }

    if(mode == 0)
    {
        writeByteMatrix(fd1, bytenum, addr1);
    } else
    {
        while(fgets(line, 512, tmplfp) != NULL)
        {
            if((strstr(line, "<BYTEARRAY_0>")) != NULL)
            {
                writeByteMatrix(fd1, 0, addr1);
                if(mode == 2) { writeByteMatrix(fd2, 0, addr2); }
            }
            else if((strstr(line, "<BYTEARRAY_1>")) != NULL)
            {
                writeByteMatrix(fd1, 1, addr1);
                if(mode == 2) { writeByteMatrix(fd2, 1, addr2); }
            }
            else if((strstr(line, "<BYTEARRAY_2>")) != NULL)
            {
                writeByteMatrix(fd1, 2, addr1);
                if(mode == 2) { writeByteMatrix(fd2, 2, addr2); }
            }
            else if((strstr(line, "<BYTEARRAY_3>")) != NULL)
            {
                writeByteMatrix(fd1, 3, addr1);
                if(mode == 2) { writeByteMatrix(fd2, 3, addr2); }
            } else
            {
                printf("%s", line);
            }
        }
	}

    close(fd1);
    if(mode == 1) { fclose(tmplfp); }
    if(mode == 2) { close(fd2); }
    return 0;
}

