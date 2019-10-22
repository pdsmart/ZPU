#ifndef __ZSTDIO_H__
#define __ZSTDIO_H__

#ifndef NOPOSIX

#include <sys/types.h>
#include <stdarg.h>

struct __zFILE {
    int fd;
};

typedef struct __zFILE FILE;

#ifdef __cplusplus
extern "C" {
#endif

int vsnprintf(char *str, size_t size, const char *format, va_list ap);
int printf(const char *format, ...);
int fprintf(FILE *stream, const char *format, ...);
int sprintf(char *str, const char *format, ...);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
FILE *fopen(const char *path, const char *mode);
void fclose(FILE*);
int fflush(FILE*);

int fputc(int c, FILE *stream);
int fputs(const char *s, FILE *stream);
int putc(int c, FILE *stream);
int putchar(int c);
int puts(const char *s);

typedef int fpos_t;

int fseek(FILE *stream, long offset, int whence);
long ftell(FILE *stream);
void rewind(FILE *stream);
int fgetpos(FILE *stream, fpos_t *pos);
int fsetpos(FILE *stream, fpos_t *pos);

void perror(const char *);

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

#ifdef __cplusplus
}
#endif

#endif
#endif
