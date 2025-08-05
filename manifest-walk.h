#ifndef MANIFEST_WALK_H
#define MANIFEST_WALK_H

#include "hash.h"

struct manifest_desc {
	const void *buffer;
	unsigned long size;
	const struct git_hash_algo *algo;
	struct object_id entry_oid;
};

/*
 * Initialize a manifest descriptor for walking through chunk OIDs.
 * Points the descriptor at the beginning of the manifest content.
 */
void init_manifest_desc(struct manifest_desc *desc, const void *buffer, unsigned long size, const struct git_hash_algo *algo);

/*
 * Get the next chunk OID from the manifest.
 * Returns 1 if an OID was read, 0 if at end of manifest.
 * On success, the OID is stored in desc->entry_oid.
 */
int manifest_entry(struct manifest_desc *desc);

/*
 * Extract current OID without advancing.
 * Returns pointer to current position's OID, or NULL if invalid.
 */
const struct object_id *manifest_entry_extract(struct manifest_desc *desc);

#endif /* MANIFEST_WALK_H */