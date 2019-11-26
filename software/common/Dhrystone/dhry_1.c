/*
 ****************************************************************************
 *
 *                   "DHRYSTONE" Benchmark Program
 *                   -----------------------------
 *                                                                            
 *  Version:    C, Version 2.1
 *                                                                            
 *  File:       dhry_1.c (part 2 of 3)
 *
 *  Date:       May 25, 1988
 *
 *  Author:     Reinhold P. Weicker
 *
 ****************************************************************************
 */

#include "zpu-types.h"
#include "dhry.h"
#include "zpu_soc.h"
#include <string.h>
#include <stdarg.h>
#include "xprintf.h"

/* Global Variables: */

Rec_Pointer     Ptr_Glob,
                Next_Ptr_Glob;
int             Int_Glob;
Boolean         Bool_Glob;
char            Ch_1_Glob,
                Ch_2_Glob;
int             Arr_1_Glob [50];
int             Arr_2_Glob [50] [50];

Enumeration     Func_1 ();
  /* forward declaration necessary since Enumeration may not simply be int */

#ifndef REG
        Boolean Reg = false;
#define REG
        /* REG becomes defined as empty */
        /* i.e. no register variables   */
#else
        Boolean Reg = true;
#endif

/* variables for time measurement: */

#ifdef TIMES
struct tms      time_info;
                /* see library function "times" */
#define Too_Small_Time 120
                /* Measurements should last at least about 2 seconds */
#endif
#ifdef TIME
extern long     time();
                /* see library function "time"  */
#define Too_Small_Time 2
                /* Measurements should last at least 2 seconds */
#endif

long            Begin_Time,
                End_Time,
                User_Time;
long            Microseconds,
                Dhrystones_Per_Second,
                Vax_Mips;
                
/* end of variables for time measurement */

int             Number_Of_Runs = 50000;

//long _readMilliseconds()
//{
//	return(TIMER_MILLISECONDS + (TIMER_SECONDS*1000) + (TIMER_MINUTES);
//}

#if 0
#define strcpy _strcpy

_strcpy(char *dst,const char *src)
{
	while(*dst++=*src++);
}
#endif

Rec_Type rec1;
Rec_Type rec2;


// Keep anything remotely large off the stack...
Str_30          Str_1_Loc;
Str_30          Str_2_Loc;

int main_dhry ()
/*****/

  /* main program, corresponds to procedures        */
  /* Main and Proc_0 in the Ada version             */
{
        One_Fifty       Int_1_Loc;
  REG   One_Fifty       Int_2_Loc;
        One_Fifty       Int_3_Loc;
  REG   char            Ch_Index;
        Enumeration     Enum_Loc;
  REG   int             Run_Index;

  /* Initializations */

//  Next_Ptr_Glob = (Rec_Pointer) malloc (sizeof (Rec_Type));
//  Ptr_Glob = (Rec_Pointer) malloc (sizeof (Rec_Type));

  Next_Ptr_Glob = &rec1;
  Ptr_Glob = &rec2;

  Ptr_Glob->Ptr_Comp                    = Next_Ptr_Glob;
  Ptr_Glob->Discr                       = Ident_1;
  Ptr_Glob->variant.var_1.Enum_Comp     = Ident_3;
  Ptr_Glob->variant.var_1.Int_Comp      = 40;
  strcpy (Ptr_Glob->variant.var_1.Str_Comp, 
          "DHRYSTONE PROGRAM, SOME STRING");
  strcpy (Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");

  Arr_2_Glob [8][7] = 10;
        /* Was missing in published program. Without this statement,    */
        /* Arr_2_Glob [8][7] would have an undefined value.             */
        /* Warning: With 16-Bit processors and Number_Of_Runs > 32000,  */
        /* overflow may occur for this array element.                   */
  xprintf ("\r\n");
  xprintf ("Dhrystone Benchmark, Version 2.1 (Language: C)\r\n");
  xprintf ("\r\n");
  if (Reg)
  {
    xprintf ("Program compiled with 'register' attribute\r\n");
    xprintf ("\r\n");
  }
  else
  {
    xprintf ("Program compiled without 'register' attribute\r\n");
    xprintf ("\r\n");
  }
  Number_Of_Runs;

  xprintf ("Execution starts, %d runs through Dhrystone\r\n", Number_Of_Runs);

  /***************/
  /* Start timer */
  /***************/

#if 0
#ifdef TIMES
  times (&time_info);
  Begin_Time = (long) time_info.tms_utime;
#endif
#ifdef TIME
  Begin_Time = time ( (long *) 0);
#endif
#else
  //Begin_Time = _readMilliseconds();
  TIMER_MILLISECONDS_UP = 0;
  Begin_Time = 0;
#endif
  for (Run_Index = 1; Run_Index <= Number_Of_Runs; ++Run_Index)
  {
    Proc_5();
    Proc_4();
      /* Ch_1_Glob == 'A', Ch_2_Glob == 'B', Bool_Glob == true */
    Int_1_Loc = 2;
    Int_2_Loc = 3;
    strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
    Enum_Loc = Ident_2;
    Bool_Glob = ! Func_2 (Str_1_Loc, Str_2_Loc);
      /* Bool_Glob == 1 */
    while (Int_1_Loc < Int_2_Loc)  /* loop body executed once */
    {
      Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
        /* Int_3_Loc == 7 */
      Proc_7 (Int_1_Loc, Int_2_Loc, &Int_3_Loc);
        /* Int_3_Loc == 7 */
      Int_1_Loc += 1;
    } /* while */
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
    Proc_8 (Arr_1_Glob, Arr_2_Glob, Int_1_Loc, Int_3_Loc);
      /* Int_Glob == 5 */
    Proc_1 (Ptr_Glob);
    for (Ch_Index = 'A'; Ch_Index <= Ch_2_Glob; ++Ch_Index)
                             /* loop body executed twice */
    {
      if (Enum_Loc == Func_1 (Ch_Index, 'C'))
          /* then, not executed */
        {
        Proc_6 (Ident_1, &Enum_Loc);
        strcpy (Str_2_Loc, "DHRYSTONE PROGRAM, 3'RD STRING");
        Int_2_Loc = Run_Index;
        Int_Glob = Run_Index;
        }
    }
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
    Int_2_Loc = Int_2_Loc * Int_1_Loc;
    Int_1_Loc = Int_2_Loc / Int_3_Loc;
    Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc;
      /* Int_1_Loc == 1, Int_2_Loc == 13, Int_3_Loc == 7 */
    Proc_2 (&Int_1_Loc);
      /* Int_1_Loc == 5 */

  } /* loop "for Run_Index" */

  /**************/
  /* Stop timer */
  /**************/
  
#if 0
#ifdef TIMES
  times (&time_info);
  End_Time = (long) time_info.tms_utime;
#endif
#ifdef TIME
  End_Time = time ( (long *) 0);
#endif
#else
  //End_Time = _readMilliseconds();
  End_Time = TIMER_MILLISECONDS_UP;
#endif

#if 0  
  xprintf ("Execution ends\r\n");
  xprintf ("\r\n");
  xprintf ("Final values of the variables used in the benchmark:\r\n");
  xprintf ("\r\n");
  xprintf ("Int_Glob:            %d\r\n", Int_Glob);
  xprintf ("        should be:   %d\r\n", 5);
  xprintf ("Bool_Glob:           %d\r\n", Bool_Glob);
  xprintf ("        should be:   %d\r\n", 1);
  xprintf ("Ch_1_Glob:           %c\r\n", Ch_1_Glob);
  xprintf ("        should be:   %c\r\n", 'A');
  xprintf ("Ch_2_Glob:           %c\r\n", Ch_2_Glob);
  xprintf ("        should be:   %c\r\n", 'B');
  xprintf ("Arr_1_Glob[8]:       %d\r\n", Arr_1_Glob[8]);
  xprintf ("        should be:   %d\r\n", 7);
  xprintf ("Arr_2_Glob[8][7]:    %d\r\n", Arr_2_Glob[8][7]);
  xprintf ("        should be:   Number_Of_Runs + 10\r\n");
  xprintf ("Ptr_Glob->\r\n");
  xprintf ("  Ptr_Comp:          %d\r\n", (int) Ptr_Glob->Ptr_Comp);
  xprintf ("        should be:   (implementation-dependent)\r\n");
  xprintf ("  Discr:             %d\r\n", Ptr_Glob->Discr);
  xprintf ("        should be:   %d\r\n", 0);
  xprintf ("  Enum_Comp:         %d\r\n", Ptr_Glob->variant.var_1.Enum_Comp);
  xprintf ("        should be:   %d\r\n", 2);
  xprintf ("  Int_Comp:          %d\r\n", Ptr_Glob->variant.var_1.Int_Comp);
  xprintf ("        should be:   %d\r\n", 17);
  xprintf ("  Str_Comp:          %s\r\n", Ptr_Glob->variant.var_1.Str_Comp);
  xprintf ("        should be:   DHRYSTONE PROGRAM, SOME STRING\r\n");
  xprintf ("Next_Ptr_Glob->\r\n");
  xprintf ("  Ptr_Comp:          %d\r\n", (int) Next_Ptr_Glob->Ptr_Comp);
  xprintf ("        should be:   (implementation-dependent), same as above\r\n");
  xprintf ("  Discr:             %d\r\n", Next_Ptr_Glob->Discr);
  xprintf ("        should be:   %d\r\n", 0);
  xprintf ("  Enum_Comp:         %d\r\n", Next_Ptr_Glob->variant.var_1.Enum_Comp);
  xprintf ("        should be:   %d\r\n", 1);
  xprintf ("  Int_Comp:          %d\r\n", Next_Ptr_Glob->variant.var_1.Int_Comp);
  xprintf ("        should be:   %d\r\n", 18);
  xprintf ("  Str_Comp:          %s\r\n",
                                Next_Ptr_Glob->variant.var_1.Str_Comp);
  xprintf ("        should be:   DHRYSTONE PROGRAM, SOME STRING\r\n");
  xprintf ("Int_1_Loc:           %d\r\n", Int_1_Loc);
  xprintf ("        should be:   %d\r\n", 5);
  xprintf ("Int_2_Loc:           %d\r\n", Int_2_Loc);
  xprintf ("        should be:   %d\r\n", 13);
  xprintf ("Int_3_Loc:           %d\r\n", Int_3_Loc);
  xprintf ("        should be:   %d\r\n", 7);
  xprintf ("Enum_Loc:            %d\r\n", Enum_Loc);
  xprintf ("        should be:   %d\r\n", 1);
  xprintf ("Str_1_Loc:           %s\r\n", Str_1_Loc);
  xprintf ("        should be:   DHRYSTONE PROGRAM, 1'ST STRING\r\n");
  xprintf ("Str_2_Loc:           %s\r\n", Str_2_Loc);
  xprintf ("        should be:   DHRYSTONE PROGRAM, 2'ND STRING\r\n");
  xprintf ("\r\n");
#endif

  User_Time = End_Time - Begin_Time;
  xprintf ("User time: %d\r\n", (int)User_Time);
  
  if (User_Time < Too_Small_Time)
  {
    xprintf ("Measured time too small to obtain meaningful results\r\n");
    xprintf ("Please increase number of runs\r\n");
    xprintf ("\r\n");
  }
/*   else */
  {
#if 0
#ifdef TIME
    Microseconds = (User_Time * Mic_secs_Per_Second )
                        /  Number_Of_Runs;
    Dhrystones_Per_Second =  Number_Of_Runs / User_Time;
    Vax_Mips = (Number_Of_Runs*1000) / (1757*User_Time);
#else
    Microseconds = (float) User_Time * Mic_secs_Per_Second 
                        / ((float) HZ * ((float) Number_Of_Runs));
    Dhrystones_Per_Second = ((float) HZ * (float) Number_Of_Runs)
                        / (float) User_Time;
    Vax_Mips = Dhrystones_Per_Second / 1757.0;
#endif
#else
    Microseconds = (1000*User_Time) / Number_Of_Runs;
    Dhrystones_Per_Second =  (Number_Of_Runs*1000) / User_Time;
    Vax_Mips = (Number_Of_Runs*569) / User_Time;
#endif 
    xprintf ("Microseconds for one run through Dhrystone: ");
    xprintf ("%d \r\n", (int)Microseconds);
    xprintf ("Dhrystones per Second:                      ");
    xprintf ("%d \r\n", (int)Dhrystones_Per_Second);
    xprintf ("VAX MIPS rating * 1000 = %d \r\n",(int)Vax_Mips);
    xprintf ("\r\n");
  }
  
  return 0;
}


Proc_1 (Ptr_Val_Par)
/******************/

REG Rec_Pointer Ptr_Val_Par;
    /* executed once */
{
  REG Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;  
                                        /* == Ptr_Glob_Next */
  /* Local variable, initialized with Ptr_Val_Par->Ptr_Comp,    */
  /* corresponds to "rename" in Ada, "with" in Pascal           */
  
  structassign (*Ptr_Val_Par->Ptr_Comp, *Ptr_Glob); 
  Ptr_Val_Par->variant.var_1.Int_Comp = 5;
  Next_Record->variant.var_1.Int_Comp 
        = Ptr_Val_Par->variant.var_1.Int_Comp;
  Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
  Proc_3 (&Next_Record->Ptr_Comp);
    /* Ptr_Val_Par->Ptr_Comp->Ptr_Comp 
                        == Ptr_Glob->Ptr_Comp */
  if (Next_Record->Discr == Ident_1)
    /* then, executed */
  {
    Next_Record->variant.var_1.Int_Comp = 6;
    Proc_6 (Ptr_Val_Par->variant.var_1.Enum_Comp, 
           &Next_Record->variant.var_1.Enum_Comp);
    Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    Proc_7 (Next_Record->variant.var_1.Int_Comp, 10, 
           &Next_Record->variant.var_1.Int_Comp);
  }
  else /* not executed */
    structassign (*Ptr_Val_Par, *Ptr_Val_Par->Ptr_Comp);
} /* Proc_1 */


Proc_2 (Int_Par_Ref)
/******************/
    /* executed once */
    /* *Int_Par_Ref == 1, becomes 4 */

One_Fifty   *Int_Par_Ref;
{
  One_Fifty  Int_Loc;  
  Enumeration   Enum_Loc;

  Int_Loc = *Int_Par_Ref + 10;
  do /* executed once */
    if (Ch_1_Glob == 'A')
      /* then, executed */
    {
      Int_Loc -= 1;
      *Int_Par_Ref = Int_Loc - Int_Glob;
      Enum_Loc = Ident_1;
    } /* if */
  while (Enum_Loc != Ident_1); /* true */
} /* Proc_2 */


Proc_3 (Ptr_Ref_Par)
/******************/
    /* executed once */
    /* Ptr_Ref_Par becomes Ptr_Glob */

Rec_Pointer *Ptr_Ref_Par;

{
  if (Ptr_Glob != Null)
    /* then, executed */
    *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
  Proc_7 (10, Int_Glob, &Ptr_Glob->variant.var_1.Int_Comp);
} /* Proc_3 */


Proc_4 () /* without parameters */
/*******/
    /* executed once */
{
  Boolean Bool_Loc;

  Bool_Loc = Ch_1_Glob == 'A';
  Bool_Glob = Bool_Loc | Bool_Glob;
  Ch_2_Glob = 'B';
} /* Proc_4 */


Proc_5 () /* without parameters */
/*******/
    /* executed once */
{
  Ch_1_Glob = 'A';
  Bool_Glob = false;
} /* Proc_5 */


        /* Procedure for the assignment of structures,          */
        /* if the C compiler doesn't support this feature       */
#ifdef  NOSTRUCTASSIGN
memcpy (d, s, l)
register char   *d;
register char   *s;
register int    l;
{
        while (l--) *d++ = *s++;
}
#endif


