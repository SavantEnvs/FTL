// Harness: in-memory GZIP reader used by Teleporter / config (src/zip/gzip.c).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "zip/gzip.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	unsigned char *in = malloc(size ? size : 1);
	if(in == NULL)
		return 0;
	memcpy(in, data, size);

	unsigned char *out = NULL;
	mz_ulong outsize = 0;
	if(inflate_buffer(in, (mz_ulong)size, &out, &outsize))
		free(out);
	free(in);
	return 0;
}
