// Harness: DNS wire-format parsing as the Pi-hole-patched dnsmasq does it for every
// received query (src/dnsmasq/rfc1035.c, src/dnsmasq/edns0.c) plus FTL's own EDNS(0)
// pseudoheader interpreter (src/edns0.c), chained the way forward.c chains them.
#define FTLDNS
#include "dnsmasq/dnsmasq.h"
#undef __USE_XOPEN
#include "FTL.h"
#include "edns0.h"
#include "config/config.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
	(void)argc; (void)argv;
	// The only dnsmasq state the stateless packet parsers dereference
	daemon = calloc(1, sizeof(struct daemon));
	daemon->namebuff = calloc(MAXDNAME * 2, 1);
	daemon->edns_pktsz = 4096;
	// Exercise the ECS branch and the hex-dump branches of FTL_parse_pseudoheaders()
	config.dns.EDNS0ECS.v.b = true;
	config.debug.edns0.v.b = true;
	return 0;
}

static unsigned char *dup_exact(const uint8_t *data, size_t size)
{
	unsigned char *p = malloc(size);
	memcpy(p, data, size);
	return p;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	// dnsmasq drops anything shorter than a DNS header before parsing
	// (receive_query(): n < sizeof(struct dns_header))
	if(size < sizeof(struct dns_header))
		return -1;

	unsigned char *buf = dup_exact(data, size);
	struct dns_header *header = (struct dns_header *)buf;

	// Query path: forward.c find_pseudoheader() -> FTL_parse_pseudoheaders()
	size_t plen = 0;
	unsigned char *sizep = NULL;
	int is_sign = 0, is_last = 0;
	unsigned char *pheader = find_pseudoheader(header, size, &plen, &sizep, &is_sign, &is_last);
	if(pheader != NULL)
		FTL_parse_pseudoheaders(pheader, plen);

	// Question section and its extraction
	unsigned short qtype = 0, qclass = 0;
	extract_request(header, size, daemon->namebuff, &qtype, &qclass);
	check_for_ignored_address(header, size);

	free(buf);

	// Reply path helpers that rewrite the packet in place get their own copy
	buf = dup_exact(data, size);
	header = (struct dns_header *)buf;
	pheader = find_pseudoheader(header, size, &plen, NULL, NULL, NULL);
	if(pheader != NULL)
		resize_packet(header, size, pheader, plen);
	free(buf);
	return 0;
}
