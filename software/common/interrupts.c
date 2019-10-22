#include "zpu-types.h"
#include "zpu_soc.h"
#include "interrupts.h"

extern void (*_inthandler_fptr)();

void SetIntHandler(void(*handler)())
{
    _inthandler_fptr=handler;
}

// Method to disable interrupts.
//
__inline void DisableInterrupts()
{
    INTERRUPT_CTRL(INTR0) = 0;
}

#if !defined(FUNCTIONALITY) || FUNCTIONALITY <= 1
// Method to enable individual interrupts.
//
static uint32_t intrSetting = 0;
void EnableInterrupt(uint32_t intrMask)
{
    uint32_t currentIntr = INTERRUPT_CTRL(INTR0);
    INTERRUPT_CTRL(INTR0) = 0;
    currentIntr &= ~intrMask;
    currentIntr |= intrMask;
    intrSetting = currentIntr;
    INTERRUPT_CTRL(INTR0) = intrSetting;
}

// Method to disable individual interrupts.
//
void DisableInterrupt(uint32_t intrMask)
{
    intrSetting = INTERRUPT_CTRL(INTR0);
    INTERRUPT_CTRL(INTR0) = 0;
    intrSetting &= ~intrMask;
    INTERRUPT_CTRL(INTR0) = intrSetting;
}

// Method to enable interrupts.
//
__inline void EnableInterrupts()
{
    INTERRUPT_CTRL(INTR0) = intrSetting;
}
#endif
