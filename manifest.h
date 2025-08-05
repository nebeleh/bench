#ifndef MANIFEST_H
#define MANIFEST_H

#include "object.h"

extern const char *manifest_type;

struct manifest {
	struct object object;
	/*
	 * Manifest contains an ordered list of blob/chunk OIDs.
	 * We don't store the OIDs in memory - use manifest-walk.h
	 * to iterate through them when needed.
	 */
	void *buffer;
	unsigned long size;
};

struct manifest *lookup_manifest(struct repository *r, const struct object_id *oid);

/**
 * Parse a manifest buffer and extract the chunk OID references.
 * Format: One hex OID per line (40 chars for SHA-1, 64 for SHA-256).
 * Returns 0 on success, -1 on error.
 **/
int parse_manifest_buffer(struct repository *r, struct manifest *item, void *buffer, unsigned long size);

/**
 * Create a manifest object that references the given blob OIDs.
 * For now, typically called with a single OID (entire file as one chunk).
 * Returns the created manifest object.
 **/
struct manifest *create_manifest(struct repository *r, const struct object_id *chunk_oids, size_t chunk_count);

/**
 * Free the memory associated with a manifest's chunk list.
 **/
void free_manifest(struct manifest *m);

#endif /* MANIFEST_H */