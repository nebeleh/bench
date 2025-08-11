#ifndef MANIFEST_H
#define MANIFEST_H

#include "object.h"

struct oid_array;

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
 * Write a manifest object directly to the object database.
 * This is a simplified interface for object-file.c that handles the manifest
 * format internally based on the configured version.
 * Returns 0 on success, -1 on error.
 **/
int write_manifest_object(struct repository *r, struct object_id *oid,
                         unsigned long total_size, size_t chunk_count,
                         const struct object_id *chunk_oids);

/**
 * Hash a manifest object without writing it to the database.
 * This creates the same manifest format as write_manifest_object but only
 * computes the hash. Used when INDEX_WRITE_OBJECT flag is not set.
 * Returns 0 on success, -1 on error.
 **/
int hash_manifest_object(struct repository *r, struct object_id *oid,
                        unsigned long total_size, size_t chunk_count,
                        const struct object_id *chunk_oids);

/**
 * Free the memory associated with a manifest's chunk list.
 **/
void free_manifest(struct manifest *m);

/* Streaming interface for manifest content */
struct manifest_stream;

/**
 * Open a stream to read content from a manifest.
 * This transparently handles reading across multiple chunks.
 * Returns NULL on error.
 **/
struct manifest_stream *open_manifest_stream(struct repository *r,
                                             const struct object_id *manifest_oid,
                                             unsigned long *size);

/**
 * Read data from a manifest stream.
 * Transparently handles chunk boundaries - consumers don't need to
 * know about the underlying chunking.
 * Returns the number of bytes read, 0 at end of stream, or -1 on error.
 **/
ssize_t read_manifest_stream(struct manifest_stream *stream, void *buf, size_t count);

/**
 * Close a manifest stream and free associated resources.
 * Returns 0 on success, -1 on error.
 **/
int close_manifest_stream(struct manifest_stream *stream);

/**
 * Stream manifest content to a file descriptor.
 * This is a convenience function that handles the entire streaming process.
 * Returns 0 on success, -1 on error.
 **/
int stream_manifest_to_fd(struct repository *r, int fd, const struct object_id *manifest_oid);

/**
 * Get the total size and chunk OIDs from a manifest.
 * This is used for reachability analysis and filtering.
 * The chunk_oids array will be populated with the OIDs.
 * Returns 0 on success, -1 on error.
 * On success, *total_size contains the sum of all chunk sizes.
 **/
int get_manifest_chunk_oids(struct repository *r,
                           const struct object_id *manifest_oid,
                           unsigned long *total_size,
                           struct oid_array *chunk_oids);

#endif /* MANIFEST_H */