#ifndef SPI_H
#define SPI_H

#include "zpu-types.h"

#ifdef __cplusplus
extern "C" {
#endif

int spi_init(uint32_t device);
int sd_read_sector(uint32_t device, unsigned long lba,unsigned char *buf);
int sd_write_sector(uint32_t device, unsigned long lba,unsigned char *buf); // FIXME - stub

#ifdef __cplusplus
}
#endif

#endif
