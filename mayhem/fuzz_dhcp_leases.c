// Harness: dhcp.leases validator run on a Teleporter import (src/zip/teleporter.c).
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

bool valid_dhcp_leases(const char *data, const size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	valid_dhcp_leases((const char *)data, size);
	return 0;
}
