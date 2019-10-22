
/* Memory Definitions for a ZPU program running entirely from boot / stack RAM */

MEMORY
{
  BOOT (rx) : ORIGIN = ,  LENGTH =       /* Boot section contains just the initial jump */
  CODE (rx) : ORIGIN = , LENGTH =       /* Up to the end of the ROM first less stack space */
}


/* Section Definitions */

SECTIONS
{
  /* first section is .fixed_vectors which is used for startup code */
  . = ;
  _bramstart = . ;
  __boot_start__ = . ;
  .fixed_vectors :
  {
	KEEP(*(.fixed_vectors)) /* Seed section - allows -gc-sections */
  }>BOOT
  __boot_end__ = . ;

/*  . = 0x4000060; */
  /* Remaining code sections */
  __text_start__ = . ;
  .text :
  {
	. = ALIGN(4);
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
  __rodata_start__ = . ;
  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
  . = ALIGN(4);
  } >CODE
  __rodata_end__ = . ;
  _bramend = . ;

  /* .data section which is used for initialized data.
     Since we don't want any writable data within the ROM
     itself, we put this stuff in a "trap" section. */
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
  .bss :
  {
    __bss_start = . ;
    __bss_start__ = . ;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
	__bss_end__ = . ;
  } >CODE
  _dataend = . ;
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
