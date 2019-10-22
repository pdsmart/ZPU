
/* Memory Definitions for a ZPU application running within RAM (either a block of BRAM, DRAM) seperate to tbe Boot BRAM.*/

MEMORY
{
  BOOT (rx) : ORIGIN = 0x009000,  LENGTH = 0x000100    /* Boot section which shouldnt exist in an app, so a link trap as warning */
  CODE (rx) : ORIGIN = 0x009100,  LENGTH = 0x003700     /* Up to the end of the RAM first less stack space */
}

/* Section Definitions */

SECTIONS
{
  /* first section is .fixed_vectors which is used for startup code */
  . = 0x009000 ;
  _ramstart = . ;
  __boot_start__ = . ;
  .fixed_vectors :
  {
	KEEP(*(.fixed_vectors)) /* Seed section - allows -gc-sections */
  }>BOOT
  __boot_end__ = . ;

  /* Remaining code sections */
  . = ALIGN(4);
  __text_start__ = . ;
  .text :
  {
    *(.text)                   /* remaining code */
    *(.text.*)                   /* remaining code */
	. = ALIGN(4);
	__ctors_start__ = . ;
	KEEP(*(.ctors))
	KEEP(*(.ctors.*))
	__ctors_end__ = . ;
    . = ALIGN(4);
	__dtors_start__ = . ;
	KEEP(*(.dtors))
	KEEP(*(.dtors.*))
	__dtors_end__ = . ;
  } >CODE
  __text_end__ = . ;

  /* .rodata section which is used for read-only data (constants) */
  . = ALIGN(4);
  __rodata_start__ = . ;
  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
  } >CODE
  . = ALIGN(4);
  __rodata_end__ = . ;
  _ramend = . ;

  /* .data section which is used for initialized data. */
  . = ALIGN(4);
  _datastart = . ;
  .data :
  {
    _data = . ;
    __data_start__ = . ;
    *(.data)
    *(.data.*)
    SORT(CONSTRUCTORS)
    . = ALIGN(4);
    __data_end__ = . ;
  } >CODE

  /* .bss section which is used for uninitialized data */
  . = ALIGN(4);
  .bss :
  {
    __bss_start = . ;
    __bss_start__ = . ;
    *(.bss)
    *(.bss.*)
    *(COMMON)
	__bss_end__ = . ;
	_end = . ;
  } >CODE
  _dataend = . ;

  /* Top of stack pointer, used for sbrk validation. */
  _stack = 0x1fff8 ;

	/* Debug information */
  .debug_loc 0 : { *(.debug_loc) }
  .debug_abbrev 0 : { *(.debug_abbrev) }
  .debug_str 0 : { *(.debug_str) }
  .debug_info 0 : { *(.debug_info) }
  .debug_line 0 : { *(.debug_line) }
  .debug_frame 0 : { *(.debug_frame) }
  .debug_pubnames 0 : { *(.debug_pubnames) }
  .debug_aranges 0 : { *(.debug_aranges) }
  .comment : { *(.comment) }
}
