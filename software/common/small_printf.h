#ifndef SMALL_PRINTF_H
#define SMALL_PRINTF_H

#ifdef DISABLE_PRINTF
#define small_printf(x,...)
#define printf(x,...)
#define puts(x)
#else
#ifdef __cplusplus
extern "C" {
#endif
int small_printf(const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#define printf small_printf
#endif

#endif

