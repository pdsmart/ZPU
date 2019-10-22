#include "keyboard.h"
#include "ps2.h"

//#include "small_printf.h"

// FIXME - create another ring buffer for ASCII keystrokes

unsigned char kblookup[2][128] =
{
	{
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,'\t',0,0,
	0,0,0,0,0,'q','1',0,
	0,0,'z','s','a','w','2',0,
	0,'c','x','d','e','4','3',0,
	0,' ','v','f','t','r','5',0,
	0,'n','b','h','g','y','6',0,
	0,0,'m','j','u','7','8',0,
	0,',','k','i','o','0','9',0,
	0,'.','/','l',';','p','-',0,
	0,0,'\'',0,'[','=',0,0,
	0,0,'\n',']',0,'#',0,0,
	0,0,0,0,0,0,'\b',0,
	0,'1',0,'4','7',0,0,0,
	'0','.','2','5','6','8',27,0,
	0,'+','3',0,'*','9',0,0
	},
	{
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,8,0,0,
	0,0,0,0,0,'Q','!',0,
	0,0,'Z','S','A','W','"',0,
	0,'C','X','D','E','$','£',0,
	0,' ','V','F','T','R','%',0,
	0,'N','B','H','G','Y','^',0,
	0,0,'M','J','U','&','*',0,
	0,'<','K','I','O',')','(',0,
	0,'>','?','L',':','P','_',0,
	0,0,'?',0,'{','+',0,0,
	0,0,'\n','}',0,'~',0,0,
	0,0,0,0,0,0,9,0,
	0,'1',0,'4','7',0,0,0,
	'0','.','2','5','6','8',27,0,
	0,'+','3',0,'*','9',0,0
	},
};

// Only need 2 bits per key in the keytable,
// so we'll use 32-bit ints to store the key statuses
// since that's more convienent for the ZPU.
// Keycode (0-255)>>4 -> Index
// Shift each 2-bit tuple by (keycode & 15)*2.
unsigned int keytable[16]={0};

#define QUAL_SHIFT 0

static int qualifiers=0;
static int leds=0;
static int fkeys=0;

int HandlePS2RawCodes()
{
	int result=0;
	static int keyup=0;
	static int extkey=0;
	int updateleds=0;
	int key;

	while((key=PS2KeyboardRead())>-1)
	{
		if(key==KEY_KEYUP)
			keyup=1;
		else if(key==KEY_EXT)
			extkey=1;
		else
		{
//			if(key<128)
//			{
				int keyidx=extkey ? 128+key : key;
				if(keyup)
					keytable[keyidx>>4]&=~(1<<((keyidx&15)*2));  // Mask off the "currently pressed" bit.
				else
					keytable[keyidx>>4]|=3<<((keyidx&15)*2);	// Currently pressed and pressed since last test.
//			}
			if(keyup==0)
			{
				int a=0;
//				printf("key %d, qual %d\n",key,qualifiers);
				if(!extkey)
				{
					a=kblookup[ (leds & 4) ? qualifiers | 1 : qualifiers][key];
//					printf("code %d\n",a);
					if(a)
						return(a);
				}
				switch(key)
				{
					case 0x58:	// Caps lock
						leds^=0x04;
						updateleds=1;
						break;
					case 0x7e:	// Scroll lock
						leds^=0x01;
						updateleds=1;
						break;
					case 0x77:	// Num lock
						leds^=0x02;
						updateleds=1;
						break;
					case 0x12:
					case 0x59:
						qualifiers|=(1<<QUAL_SHIFT);
						break;
				}
			}
			else
			{
				switch(key)
				{
					case 0x12:
					case 0x59:
						qualifiers&=~(1<<QUAL_SHIFT);
						break;
				}
			}
			extkey=0;
			keyup=0;
		}
	}
	if(updateleds)
	{
		PS2KeyboardWrite(0xed);
		PS2KeyboardWrite(leds);
	}
	return(result);
}


void ClearKeyboard()
{
	int i;
	for(i=0;i<16;++i)
		keytable[i]=0;
}

int TestKey(int rawcode)
{
	int result;
	DisableInterrupts();	// Make sure a new character doesn't arrive halfway through the read
	result=3&(keytable[rawcode>>4]>>((rawcode&15)*2));
	keytable[rawcode>>4]&=~(2<<((rawcode&15)*2));	// Mask off the "pressed since last test" bit.
	EnableInterrupts();
	return(result);
}

