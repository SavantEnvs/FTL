// Harness: TRE regex engine as Pi-hole drives it for user regex filters
// (src/regex.c compiles with REG_EXTENDED | REG_ICASE | REG_NOSUB).
// Input: "<pattern>\0<subject>"; without a NUL the whole input is the pattern.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "tre-regex/regex.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	const uint8_t *nul = memchr(data, '\0', size);
	const size_t plen = nul != NULL ? (size_t)(nul - data) : size;
	const size_t slen = nul != NULL ? size - plen - 1 : 0;

	char *pattern = malloc(plen + 1);
	char *subject = malloc(slen + 1);
	if(pattern == NULL || subject == NULL)
		goto out;
	memcpy(pattern, data, plen);
	pattern[plen] = '\0';
	memcpy(subject, nul != NULL ? nul + 1 : data, slen);
	subject[slen] = '\0';

	regex_t re;
	if(regcomp(&re, pattern, REG_EXTENDED | REG_ICASE | REG_NOSUB) == 0)
	{
		regexec(&re, subject, 0, NULL, 0);
		regfree(&re);
	}
out:
	free(pattern);
	free(subject);
	return 0;
}
