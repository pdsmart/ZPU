// zpuramgen.c
//
// Program to turn a binary file into a VHDL lookup table.
//   by Adam Pierce
//   29-Feb-2008
//
// This software is free to use by anyone for any purpose.
//

#include <unistd.h>
#include <stdio.h>

typedef unsigned char BYTE;

main(int argc, char **argv)
{
       BYTE    opcode[4];
       int     fd;
       int     addr = 0;
       int     bytenum;
       ssize_t s;

// Check the user has given us an input file.
       if(argc < 3)
       {
               printf("Usage: %s <0-3 = byte> <binary_file>\n\n", argv[0]);
               return 1;
       }

       bytenum = atoi(argv[1]);
       if(bytenum < 0 || bytenum > 3)
       {
               perror("Illegal byte number");
               return 2;
       }

// Open the input file.
       fd = open(argv[2], 0);
       if(fd == -1)
       {
               perror("File Open");
               return 2;
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
               printf("%6d => x\"%02x\",\n", addr++, opcode[bytenum]);
       }

       close(fd);
       return 0;
}

