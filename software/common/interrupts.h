#ifndef INTERRUPTS_H
#define INTERRUPTS_H

#ifdef __cplusplus
extern "C" {
#endif

void SetIntHandler(void(*handler)());
void EnableInterrupt(uint32_t);
void DisableInterrupt(uint32_t);
__inline void DisableInterrupts();
__inline void EnableInterrupts();

#ifdef __cplusplus
}
#endif

#endif

