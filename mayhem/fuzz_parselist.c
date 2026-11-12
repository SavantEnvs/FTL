// Harness: gravity adlist parser behind `pihole-FTL gravity parseList` (src/tools/gravity-parseList.c).
// Runs the real file-based entry point in check-only mode (no database is written) on a
// scratch file created under $TMPDIR.
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int gravity_parseList(const char *infile, const char *outfile, const char *adlistID,
                      const bool checkOnly, const bool antigravity, const char *source_url);

static char path[4096];
static char sink[1 << 16];

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	// The parser narrates progress on stdout; keep that in a fixed buffer rewound per input
	stdout = fmemopen(sink, sizeof(sink), "w");
	if(stdout == NULL)
		return 1;
	const char *tmp = getenv("TMPDIR");
	snprintf(path, sizeof(path), "%s/ftl-parselist-XXXXXX", tmp != NULL && tmp[0] != '\0' ? tmp : "/tmp");
	return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	// First byte selects the mode so one corpus covers all three call shapes
	if(size < 1)
		return -1;
	rewind(stdout);
	const bool antigravity = data[0] & 1;
	const bool local = data[0] & 2;
	data++; size--;

	char tmpl[sizeof(path)];
	memcpy(tmpl, path, sizeof(tmpl));
	const int fd = mkstemp(tmpl);
	if(fd < 0)
		return 0;
	size_t off = 0;
	while(off < size)
	{
		const ssize_t w = write(fd, data + off, size - off);
		if(w <= 0)
			break;
		off += (size_t)w;
	}
	close(fd);

	gravity_parseList(tmpl, "/dev/null", "1", true, antigravity,
	                  local ? "file:///etc/hosts" : "https://example.com/hosts.txt");
	unlink(tmpl);
	return 0;
}
