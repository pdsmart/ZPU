#include "zpu-types.h"
#include "zpu_soc.h"
//#include "small_printf.h"

#include "ps2.h"
#include "interrupts.h"
#include "keyboard.h"

void ps2_ringbuffer_init(struct ps2_ringbuffer *r)
{
	r->in_hw=0;
	r->in_cpu=0;
	r->out_hw=0;
	r->out_cpu=0;
}

void ps2_ringbuffer_write(struct ps2_ringbuffer *r,int in)
{
	while(r->out_hw==((r->out_cpu+1)&(PS2_RINGBUFFER_SIZE-1)))
		;
//	printf("w: %d, %d\n, %d\n",r->out_hw,r->out_cpu,in);
	DisableInterrupts();
	r->outbuf[r->out_cpu]=in;
	r->out_cpu=(r->out_cpu+1) & (PS2_RINGBUFFER_SIZE-1);
	PS2Handler();
	EnableInterrupts();
}


int ps2_ringbuffer_read(struct ps2_ringbuffer *r)
{
	unsigned char result;
	if(r->in_hw==r->in_cpu)
		return(-1);	// No characters ready
	result=r->inbuf[r->in_cpu];
	r->in_cpu=(r->in_cpu+1) & (PS2_RINGBUFFER_SIZE-1);
	return(result);
}

int ps2_ringbuffer_count(struct ps2_ringbuffer *r)
{
	if(r->in_hw>=r->in_cpu)
		return(r->in_hw-r->in_cpu);
	return(r->in_hw+PS2_RINGBUFFER_SIZE-r->in_cpu);
}

struct ps2_ringbuffer kbbuffer;
struct ps2_ringbuffer mousebuffer;


void PS2Handler()
{
	int kbd;
	int mouse;

	DisableInterrupts();
	
	kbd=PS2_KEYBOARD(PS2_0);
	mouse=PS2_MOUSE(PS2_0);

	if(kbd & (1<<BIT_PS2_RECV))
	{
		kbbuffer.inbuf[kbbuffer.in_hw]=kbd&0xff;
		kbbuffer.in_hw=(kbbuffer.in_hw+1) & (PS2_RINGBUFFER_SIZE-1);
	}
	if(kbd & (1<<BIT_PS2_CTS))
	{
		if(kbbuffer.out_hw!=kbbuffer.out_cpu)
		{
			PS2_KEYBOARD(PS2_0)=kbbuffer.outbuf[kbbuffer.out_hw];
			kbbuffer.out_hw=(kbbuffer.out_hw+1) & (PS2_RINGBUFFER_SIZE-1);
		}
	}
	if(mouse & (1<<BIT_PS2_RECV))
	{
		mousebuffer.inbuf[mousebuffer.in_hw]=mouse&0xff;
		mousebuffer.in_hw=(mousebuffer.in_hw+1) & (PS2_RINGBUFFER_SIZE-1);
	}
	if(mouse & (1<<BIT_PS2_CTS))
	{
		if(mousebuffer.out_hw!=mousebuffer.out_cpu)
		{
			PS2_MOUSE(PS2_0)=mousebuffer.outbuf[mousebuffer.out_hw];
			mousebuffer.out_hw=(mousebuffer.out_hw+1) & (PS2_RINGBUFFER_SIZE-1);
		}
	}
	GetInterrupts();	// Clear interrupt bit
	EnableInterrupts();
}

void PS2Init()
{
	ps2_ringbuffer_init(&kbbuffer);
	ps2_ringbuffer_init(&mousebuffer);
	SetIntHandler(&PS2Handler);
	ClearKeyboard();
}

