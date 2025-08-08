#include "git-compat-util.h"
#include "manifest-walk.h"
#include "hex.h"

void init_manifest_desc(struct manifest_desc *desc, const void *buffer, unsigned long size, const struct git_hash_algo *algo)
{
	desc->buffer = buffer;
	desc->size = size;
	desc->algo = algo;
	oidclr(&desc->entry_oid, algo);
}

/*
 * Parse the next OID from the manifest buffer.
 * Manifest format: one hex OID per line (40 chars for SHA-1, 64 for SHA-256)
 */
int manifest_entry(struct manifest_desc *desc)
{
	const char *buf = desc->buffer;
	const char *end;
	size_t line_len;

	if (!desc->size)
		return 0;

	/* Find end of line or end of buffer */
	end = memchr(buf, '\n', desc->size);
	if (!end)
		end = buf + desc->size;

	line_len = end - buf;

	/* Skip empty lines */
	if (line_len == 0) {
		desc->buffer = end + 1;
		desc->size -= 1;
		return manifest_entry(desc);
	}

	/* Parse the OID */
	if (get_oid_hex_algop(buf, &desc->entry_oid, desc->algo) < 0)
		return 0; /* Invalid OID */

	/* Advance buffer past this line */
	if (*end == '\n') {
		desc->buffer = end + 1;
		desc->size -= line_len + 1;
	} else {
		desc->buffer = end;
		desc->size = 0;
	}

	return 1;
}