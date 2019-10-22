#include "rafile.h"
//#include "small_printf.h"

int RARead(RAFile *file,unsigned char *pBuffer, unsigned long bytes)
{
	int result=1;
	// Since we can only read from the SD card on 512-byte aligned boundaries,
	// we need to copy in multiple pieces.
	unsigned long blockoffset=file->ptr&511;	// Offset within the current 512 block at which the previous read finished
												// Bytes blockoffset to 512 will be drained first, before reading new data.

//	printf("Blockoffset: %d\n",blockoffset);

	if(blockoffset)	// If blockoffset is zero we'll just use aligned reads and don't need to drain the buffer.
	{
		int i;
		int l=bytes;
		if(l>512)
			l=512;
//		printf("copying %d bytes to align read pointer\n",l);
		for(i=blockoffset;i<l;++i)
		{
			*pBuffer++=file->buffer[i];
		}
		file->ptr+=l-blockoffset;
		bytes-=l-blockoffset;
	}

	// We've now read any bytes left over from a previous read.  If any data remains to be read we can read it
	// in 512-byte aligned chunks, until the last block.
	while(bytes>511)
	{
//		printf("Reading 512 aligned bytes\n");
		if(!result)
			return(result);
		result&=FileRead(&file->file,pBuffer);	// Read direct to pBuffer
		FileNextSector(&file->file);
		bytes-=512;
		file->ptr+=512;
		pBuffer+=512;
//		printf("%d bytes remaining\n",bytes);
	}

	if(bytes)	// Do we have any bytes left to read?
	{
		int i;
//		printf("Reading %d bytes to complete read\n",bytes);
		result&=FileRead(&file->file,file->buffer);	// Read to temporary buffer, allowing us to preserve any leftover for the next read.
		FileNextSector(&file->file);
		for(i=0;i<bytes;++i)
		{
			*pBuffer++=file->buffer[i];
		}
		file->ptr+=bytes;
	}
	return(result);
}


int RASeek(RAFile *file,unsigned long offset,unsigned long origin)
{
	int result=1;
	unsigned long blockoffset;
	unsigned long blockaddress;
//	printf("Seeking to %d from origin %d\n",offset,origin);
	if(origin==SEEK_CUR)
		offset+=file->ptr;
	blockoffset=offset&511;
	blockaddress=offset-blockoffset;	// 512-byte-aligned...
	result&=FileSeek(&file->file,blockaddress,SEEK_SET);
	if(result && blockoffset)	// If we're seeking into the middle of a block, we need to buffer it...
	{
		result&=FileRead(&file->file,file->buffer);
		FileNextSector(&file->file);
	}
	file->ptr=offset;
	return(result);
}


int RAOpen(RAFile *file,const char *filename)
{
	int result=1;
	if(!file)
		return(0);
	result=FileOpen(&file->file,filename);
	file->size=file->file.size;
	file->ptr=0;
	return(result);
}

