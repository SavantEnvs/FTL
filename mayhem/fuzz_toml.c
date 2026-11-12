// Harness: the TOML parser behind pihole.toml and Teleporter config import (src/config/tomlc17).
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "config/tomlc17/tomlc17.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	// toml_parse() requires a NUL-terminated buffer (tomlc17.h); `size` excludes the NUL
	char *src = malloc(size + 1);
	if(src == NULL)
		return 0;
	memcpy(src, data, size);
	src[size] = '\0';

	toml_result_t res = toml_parse(src, (int)size);
	toml_free(res);
	free(src);
	return 0;
}
