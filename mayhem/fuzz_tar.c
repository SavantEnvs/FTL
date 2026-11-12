// Harness: Teleporter in-memory TAR reader (src/zip/tar.c).
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "zip/tar.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	cJSON *files = list_files_in_tar(data, size);
	cJSON_Delete(files);

	// Look up a name Teleporter really asks for, and the first entry's own
	// name (so find_file_in_tar() reaches the payload-bounds checks too)
	size_t fsize = 0;
	find_file_in_tar(data, size, "etc/pihole/pihole.toml", &fsize);

	char name[101] = { 0 };
	memcpy(name, data, size < 100 ? size : 100);
	find_file_in_tar(data, size, name, &fsize);
	return 0;
}
