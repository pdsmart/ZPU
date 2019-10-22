#include "zpu-types.h"
#include "zpu_soc.h"
#include "spi.h"
//#include "small_printf.h"

int SDHCtype;

#define cmd_reset(d)    cmd_write(d, 0x950040,0) // Use SPI mode
#define cmd_init(d)     cmd_write(d, 0xff0041,0)
#define cmd_read(d, x)  cmd_write(d, 0xff0051,x)
#define cmd_CMD8(d)     cmd_write(d, 0x870048,0x1AA)
#define cmd_CMD16(d, x) cmd_write(d, 0xFF0050,x)
#define cmd_CMD41(d)    cmd_write(d, 0x870069,0x40000000)
#define cmd_CMD55(d)    cmd_write(d, 0xff0077,0)
#define cmd_CMD58(d)    cmd_write(d, 0xff007A,0)

#ifdef SPI_DEBUG
#define DBG(x) puts(x)
#else
#define DBG(X)
#endif

unsigned char SPI_R1[6];


int SPI_GET_PUMP(uint32_t device)
{
	int r=0;
	SPI_DATA(device) = 0xFF;
	r=SPI_DATA(device);
	SPI_DATA(device) = 0xFF;
	r=(r<<8)|SPI_DATA(device);
	SPI_DATA(device) = 0xFF;
	r=(r<<8)|SPI_DATA(device);
	SPI_DATA(device) = 0xFF;
	r=(r<<8)|SPI_DATA(device);
	return(r);
}

int cmd_write(uint32_t device, unsigned long cmd, unsigned long lba)
{
	int ctr;
	int result=0xff;

	DBG("In cmd_write\n");

	SPI_DATA(device) = cmd & 255;

	DBG("Command sent\n");

	if(!SDHCtype)	// If normal SD then we have to use byte offset rather than LBA offset.
		lba<<=9;

	DBG("Sending LBA!\n");

	SPI_DATA(device) = (lba>>24)&255;
	DBG("Sent 1st byte\n");
	SPI_DATA(device) = (lba>>16)&255;
	DBG("Sent 2nd byte\n");
	SPI_DATA(device) = (lba>>8)&255;
	DBG("Sent 3rd byte\n");
	SPI_DATA(device) = lba&255;
	DBG("Sent 4th byte\n");

	DBG("Sending CRC - if any\n");

	SPI_DATA(device) = (cmd>>16)&255; // CRC, if any

	ctr=40000;

	result=SPI_DATA(device);
	while(--ctr && (result==0xff))
	{
		SPI_DATA(device) = 0xff;
		result=SPI_DATA(device);
	}
	#ifdef SPI_DEBUG
	putchar('0'+(result>>4));
	putchar('0'+(result&15));
	#endif
//	printf("Got result %d \n",result);

	return(result);
}


void spi_spin(uint32_t device)
{
//	puts("SPIspin\n");
	int i;
	for(i=0;i<200;++i)
		SPI_DATA(device) = 0xff;
//	puts("Done\n");
}


int wait_initV2(uint32_t device)
{
	int i=20000;
	int r;
	spi_spin(device);
	while(--i)
	{
		if((r=cmd_CMD55(device))==1)
		{
//			printf("CMD55 %d\n",r);
			SPI_DATA(device) = 0xff;
			if((r=cmd_CMD41(device))==0)
			{
//				printf("CMD41 %d\n",r);
				SPI_DATA(device) = 0xff;
				return(1);
			}
//			else
//				printf("CMD41 %d\n",r);
			spi_spin(device);
		}
//		else
//			printf("CMD55 %d\n",r);
	}
	return(0);
}


int wait_init(uint32_t device)
{
	int i=20;
	int r;
	SPI_DATA(device) = 0xff;
	puts("Cmd_init\n");
	while(--i)
	{
		if((r=cmd_init(device))==0)
		{
//			printf("init %d\n  ",r);
			SPI_DATA(device) = 0xff;
			return(1);
		}
//		else
//			printf("init %d\n  ",r);
		spi_spin(device);
	}
	return(0);
}


int is_sdhc(uint32_t device)
{
	int i,r;

	spi_spin(device);

	r=cmd_CMD8(device);		// test for SDHC capability
	printf("cmd_CMD8 response: %d\n",r);
	if(r!=1)
	{
		wait_init(device);
		return(0);
	}

	r=SPI_GET_PUMP(device);
	if((r&0xffff)!=0x01aa)
	{
		printf("CMD8_4 response: %d\n",r);
		wait_init(device);
		return(0);
	}

	SPI_DATA(device) = 0xff;

	// If we get this far we have a V2 card, which may or may not be SDHC...

	i=50;
	while(--i)
	{
		if(wait_initV2(device))
		{
			if((r=cmd_CMD58(device))==0)
			{
				printf("CMD58 %d\n  ",r);
				SPI_DATA(device) = 0xff;
				r=SPI_DATA(device);
				printf("CMD58_2 %d\n  ",r);
				SPI_DATA(device) = 0xff;
				SPI_DATA(device) = 0xff;
				SPI_DATA(device) = 0xff;
				SPI_DATA(device) = 0xff;
				if(r&0x40)
					return(1);
				else
					return(0);
			}
			else
				printf("CMD58 %d\n  ",r);
		}
		if(i==2)
		{
			printf("SDHC Initialization error!\n");
			return(0);
		}
	}
	return(0);
}


int spi_init(uint32_t device)
{
	int i;
	int r;
	SDHCtype=1;
	SPI_SET_CS(device, 0);	// Disable CS
	spi_spin(device);
	puts("SPI Init()\n");
	DBG("Activating CS\n");
	SPI_SET_CS(device, 1);
	i=8;
	while(--i)
	{
		if(cmd_reset(device)==1) // Enable SPI mode
			i=1;
		DBG("Sent reset command\n");
		if(i==2)
		{
			DBG("SD card initialization error!\n");
			return(0);
		}
	}
	DBG("Card responded to reset\n");
	SDHCtype=is_sdhc(device);
	if(SDHCtype)
		DBG("SDHC card detected\n");
	else // If not SDHC, Set blocksize to 512 bytes
	{
		DBG("Sending cmd16 (blocksize)\n");
		cmd_CMD16(device,1);
	}
	SPI_DATA(device) = 0xFF;
	SPI_SET_CS(device, 0);
	SPI_DATA(device) = 0xFF;
	DBG("Init done\n");

	return(1);
}


int sd_write_sector(uint32_t device, unsigned long lba,unsigned char *buf) // FIXME - Stub
{
	return(0);
}


extern void spi_readsector(long *buf);


int sd_read_sector(uint32_t device, unsigned long lba,unsigned char *buf)
{
	int result=0;
	int i;
	int r;
//	printf("sd_read_sector %d, %d\n",lba,buf);
	SPI_DATA(device) = 0xff;
	SPI_SET_CS(device, 1|(1<<SPI_FAST));
	SPI_DATA(device) = 0xff;

	r=cmd_read(device, lba);
	if(r!=0)
	{
		printf("Read command failed at %d (%d)\n",lba,r);
		return(result);
	}

	i=1500000;
	while(--i)
	{
		int v;
		SPI_DATA(device) = 0xff;
//		SPI_WAIT();
		v=SPI_DATA(device);
		if(v==0xfe)
		{
//			puts("Reading sector data\n");
//			spi_readsector((long *)buf);
			int j;
//			SPI_DATA(device) = 0xff;

			for(j=0;j<128;++j)
			{
				int t,v;

				t=SPI_GET_PUMP(device);
				*(int *)buf=t;
//				printf("%d: %d\n",buf,t);
				buf+=4;
			}

			i=1; // break out of the loop
			result=1;
		}
	}
	SPI_DATA(device) = 0xff;
	SPI_SET_CS(device, 0);
	return(result);
}

