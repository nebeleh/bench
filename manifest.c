#include "git-compat-util.h"
#include "manifest.h"
#include "object-file.h"
#include "repository.h"
#include "alloc.h"
#include "hex.h"
#include "strbuf.h"
#include "hash.h"
#include "config.h"
#include "streaming.h"
#include "convert.h"
#include "trace.h"
#include "manifest-walk.h"
#include "write-or-die.h"
#include "oid-array.h"

const char *manifest_type = "manifest";

struct manifest *lookup_manifest(struct repository *r, const struct object_id *oid)
{
	struct object *obj = lookup_object(r, oid);
	if (!obj)
		return create_object(r, oid, alloc_manifest_node(r));
	return object_as_type(obj, OBJ_MANIFEST, 0);
}

int parse_manifest_buffer(struct repository *r, struct manifest *item, void *buffer, unsigned long size)
{
	if (item->object.parsed)
		return 0;

	/*
	 * Just store the buffer like Git does for trees.
	 * We'll parse OIDs on-demand using manifest-walk.
	 */
	item->buffer = buffer;
	item->size = size;
	item->object.parsed = 1;
	return 0;
}

void free_manifest(struct manifest *m)
{
	if (!m)
		return;
	FREE_AND_NULL(m->buffer);
	m->size = 0;
}

struct manifest_stream {
	struct repository *repo;
	struct manifest_desc desc;
	void *manifest_buffer;  /* Manifest content buffer */
	unsigned long manifest_size;  /* Size of manifest */
	struct git_istream *current_chunk_stream;
	struct object_id current_chunk_oid;
	unsigned long total_size;
	unsigned long bytes_read;
	int initialized;
	int at_end;
};

/* Internal structure for parsed manifest header */
struct manifest_header {
	int version;
	unsigned long total_size;
	size_t chunk_count;
	const char *chunk_data;  /* Pointer to start of chunk OID data */
	size_t chunk_data_len;   /* Length of chunk OID data */
};

/*
 * Parse manifest header from buffer.
 * This centralizes all manifest version parsing logic.
 * Returns 0 on success, -1 on error.
 */
static int parse_manifest_header(const void *buffer, unsigned long size,
                                 struct manifest_header *header)
{
	const char *p = buffer;
	const char *end = (const char *)buffer + size;
	
	/* Parse version */
	header->version = strtol(p, (char **)&p, 10);
	if (p >= end || *p++ != '\n') {
		error("manifest missing version number");
		return -1;
	}
	
	/* Version check: We currently only support version 1 */
	if (header->version < 1) {
		error("manifest has invalid version %d", header->version);
		return -1;
	}
	if (header->version > 1) {
		error("manifest version %d is newer than supported version 1", header->version);
		return -1;
	}
	
	/* Version 1 parsing - in future, use switch(version) for other versions */
	if (header->version == 1) {
		/* Parse total size */
		header->total_size = strtoul(p, (char **)&p, 10);
		if (p >= end || *p++ != '\n') {
			error("manifest missing total size");
			return -1;
		}
		
		/* Parse chunk count */
		header->chunk_count = strtoul(p, (char **)&p, 10);
		if (p >= end || *p++ != '\n') {
			error("manifest missing chunk count");
			return -1;
		}
	}
	/* Future versions would have their parsing logic here */
	
	/* Set pointer to chunk OID data */
	header->chunk_data = p;
	header->chunk_data_len = end - p;
	
	return 0;
}

struct manifest_stream *open_manifest_stream(struct repository *r,
                                             const struct object_id *manifest_oid,
                                             unsigned long *size)
{
	struct manifest_stream *stream;
	enum object_type type;
	unsigned long manifest_size;
	void *manifest_buffer;
	struct manifest_header header;
	
	/* First verify this is actually a manifest */
	type = oid_object_info(r, manifest_oid, &manifest_size);
	if (type != OBJ_MANIFEST)
		return NULL;
	
	/* Read the manifest to get its content */
	manifest_buffer = repo_read_object_file(r, manifest_oid, &type, &manifest_size);
	if (!manifest_buffer)
		return NULL;
	
	/* Parse the manifest header using shared function */
	if (parse_manifest_header(manifest_buffer, manifest_size, &header) < 0) {
		free(manifest_buffer);
		return NULL;
	}
	
	stream = xcalloc(1, sizeof(*stream));
	stream->repo = r;
	stream->manifest_buffer = manifest_buffer;
	stream->manifest_size = manifest_size;
	stream->total_size = header.total_size;
	
	/* Initialize descriptor to point at chunk OID data */
	init_manifest_desc(&stream->desc, header.chunk_data, header.chunk_data_len, r->hash_algo);
	
	if (size)
		*size = stream->total_size;
	
	stream->initialized = 1;
	return stream;
}

static int open_next_chunk(struct manifest_stream *stream)
{
	enum object_type type;
	unsigned long chunk_size;
	
	/* Close current chunk stream if open */
	if (stream->current_chunk_stream) {
		close_istream(stream->current_chunk_stream);
		stream->current_chunk_stream = NULL;
	}
	
	/* Get next chunk OID from manifest */
	if (!manifest_entry(&stream->desc)) {
		stream->at_end = 1;
		return 0; /* End of manifest */
	}
	
	oidcpy(&stream->current_chunk_oid, &stream->desc.entry_oid);
	
	/* Open stream for this chunk
	 * TODO: For checkout operations (Phase 4), we'll need to pass
	 * a filter here instead of NULL to handle CRLF conversion,
	 * clean/smudge filters, and ident expansion.
	 */
	stream->current_chunk_stream = open_istream(stream->repo,
	                                           &stream->current_chunk_oid,
	                                           &type, &chunk_size, NULL);
	if (!stream->current_chunk_stream)
		return -1;
	
	if (type != OBJ_BLOB) {
		close_istream(stream->current_chunk_stream);
		stream->current_chunk_stream = NULL;
		return -1;
	}
	
	return 0;
}

ssize_t read_manifest_stream(struct manifest_stream *stream, void *buf, size_t count)
{
	ssize_t total_read = 0;
	char *dest = buf;
	
	if (!stream || !stream->initialized)
		return -1;
	
	if (stream->at_end)
		return 0;
	
	while (count > 0) {
		ssize_t bytes_read;
		
		/* Open first/next chunk if needed */
		if (!stream->current_chunk_stream) {
			if (open_next_chunk(stream) < 0)
				return total_read > 0 ? total_read : -1;
			if (stream->at_end)
				return total_read;
		}
		
		/* Read from current chunk */
		bytes_read = read_istream(stream->current_chunk_stream, dest, count);
		
		if (bytes_read < 0)
			return total_read > 0 ? total_read : -1;
		
		if (bytes_read == 0) {
			/* Current chunk exhausted, try next one */
			if (open_next_chunk(stream) < 0)
				return total_read > 0 ? total_read : -1;
			if (stream->at_end)
				return total_read;
			continue;
		}
		
		dest += bytes_read;
		count -= bytes_read;
		total_read += bytes_read;
		stream->bytes_read += bytes_read;
	}
	
	return total_read;
}

int close_manifest_stream(struct manifest_stream *stream)
{
	if (!stream)
		return 0;
	
	if (stream->current_chunk_stream) {
		close_istream(stream->current_chunk_stream);
		stream->current_chunk_stream = NULL;
	}
	
	free(stream->manifest_buffer);
	free(stream);
	return 0;
}

int stream_manifest_to_fd(struct repository *r, int fd, const struct object_id *manifest_oid)
{
	struct manifest_stream *stream;
	unsigned long size;
	char buf[1024 * 16]; /* 16KB buffer like Git's streaming */
	ssize_t bytes_read;
	
	stream = open_manifest_stream(r, manifest_oid, &size);
	if (!stream)
		return -1;
	
	while ((bytes_read = read_manifest_stream(stream, buf, sizeof(buf))) > 0) {
		if (write_in_full(fd, buf, bytes_read) < 0) {
			close_manifest_stream(stream);
			return -1;
		}
	}
	
	close_manifest_stream(stream);
	return bytes_read < 0 ? -1 : 0;
}

int stream_manifest_to_fd_filtered(struct repository *r, int fd, 
                                   const struct object_id *manifest_oid,
                                   struct stream_filter *filter)
{
	struct manifest_stream *stream;
	unsigned long size;
	char ibuf[1024 * 16]; /* Input buffer */
	char obuf[1024 * 16]; /* Output buffer for filtered content */
	ssize_t bytes_read;
	int result = 0;
	
	stream = open_manifest_stream(r, manifest_oid, &size);
	if (!stream) {
		if (filter)
			free_stream_filter(filter);
		return -1;
	}
	
	if (!filter || is_null_stream_filter(filter)) {
		/* No filtering needed, use simple streaming */
		while ((bytes_read = read_manifest_stream(stream, ibuf, sizeof(ibuf))) > 0) {
			if (write_in_full(fd, ibuf, bytes_read) < 0) {
				result = -1;
				break;
			}
		}
		if (bytes_read < 0)
			result = -1;
	} else {
		/* Apply filters while streaming */
		while ((bytes_read = read_manifest_stream(stream, ibuf, sizeof(ibuf))) > 0) {
			size_t to_feed = bytes_read;
			size_t to_receive = sizeof(obuf);
			
			if (stream_filter(filter, ibuf, &to_feed, obuf, &to_receive)) {
				result = -1;
				break;
			}
			
			size_t filtered_size = sizeof(obuf) - to_receive;
			if (filtered_size > 0 && write_in_full(fd, obuf, filtered_size) < 0) {
				result = -1;
				break;
			}
			
			/* Handle any unconsumed input */
			if (to_feed > 0) {
				/* This shouldn't happen with our simple streaming,
				 * but if it does, we'd need more complex buffering */
				warning("manifest streaming: filter did not consume all input");
			}
		}
		
		if (bytes_read < 0)
			result = -1;
		
		/* Drain any remaining filtered output */
		if (result == 0) {
			size_t to_receive = sizeof(obuf);
			if (stream_filter(filter, NULL, NULL, obuf, &to_receive) == 0) {
				size_t final_size = sizeof(obuf) - to_receive;
				if (final_size > 0 && write_in_full(fd, obuf, final_size) < 0)
					result = -1;
			}
		}
		
		free_stream_filter(filter);
	}
	
	close_manifest_stream(stream);
	return result;
}

/*
 * Internal function to build manifest content based on the configured version.
 * The caller is responsible for freeing the strbuf.
 * Returns 0 on success, -1 on error.
 */
static int build_manifest_content(struct repository *r, struct strbuf *buf,
                                 unsigned long total_size, size_t chunk_count,
                                 const struct object_id *chunk_oids)
{
	int manifest_version;
	size_t i;

	/*
	 * Read manifest version from config. If not set, default to 1.
	 * This allows us to control which manifest format version to use
	 * when creating new manifests.
	 */
	if (repo_config_get_int(r, "bench.manifestversion", &manifest_version))
		manifest_version = 1; /* Default to version 1 if not configured */

	/*
	 * Currently we only support creating version 1 manifests.
	 * When we add support for new versions, add cases here.
	 */
	if (manifest_version != 1) {
		error("unsupported manifest version %d for creation (only version 1 is supported)",
		      manifest_version);
		return -1;
	}

	/* Build manifest based on version */
	switch (manifest_version) {
	case 1:
		/*
		 * Manifest format v1:
		 * Line 1: Version number ("1")
		 * Line 2: Total size of all chunks combined
		 * Line 3: Number of chunks
		 * Line 4+: Chunk OIDs (one per line)
		 */
		strbuf_addf(buf, "%d\n", manifest_version);
		strbuf_addf(buf, "%lu\n", total_size);
		strbuf_addf(buf, "%zu\n", chunk_count);
		
		/* Add all chunk OIDs */
		for (i = 0; i < chunk_count; i++) {
			strbuf_addstr(buf, oid_to_hex(&chunk_oids[i]));
			strbuf_addch(buf, '\n');
		}
		break;

	/* Future versions would have their own cases here */

	default:
		/* This should not happen due to check above, but be defensive */
		error("BUG: unhandled manifest version %d", manifest_version);
		return -1;
	}

	return 0;
}

int write_manifest_object(struct repository *r, struct object_id *oid,
                         unsigned long total_size, size_t chunk_count,
                         const struct object_id *chunk_oids)
{
	struct strbuf buf = STRBUF_INIT;
	int ret;

	/* Build the manifest content */
	if (build_manifest_content(r, &buf, total_size, chunk_count, chunk_oids) < 0) {
		strbuf_release(&buf);
		return -1;
	}

	/* Write manifest object */
	ret = write_object_file(buf.buf, buf.len, OBJ_MANIFEST, oid);
	strbuf_release(&buf);
	
	return ret < 0 ? -1 : 0;
}

int hash_manifest_object(struct repository *r, struct object_id *oid,
                        unsigned long total_size, size_t chunk_count,
                        const struct object_id *chunk_oids)
{
	struct strbuf buf = STRBUF_INIT;

	/* Build the manifest content */
	if (build_manifest_content(r, &buf, total_size, chunk_count, chunk_oids) < 0) {
		strbuf_release(&buf);
		return -1;
	}

	/* Hash the manifest object without writing it */
	hash_object_file(r->hash_algo, buf.buf, buf.len, OBJ_MANIFEST, oid);
	strbuf_release(&buf);
	
	return 0;
}

int get_manifest_chunk_oids(struct repository *r,
                           const struct object_id *manifest_oid,
                           unsigned long *total_size,
                           struct oid_array *chunk_oids)
{
	enum object_type type;
	unsigned long manifest_size;
	void *manifest_buffer;
	struct manifest_header header;
	struct manifest_desc desc;
	
	/* Verify this is actually a manifest */
	type = oid_object_info(r, manifest_oid, &manifest_size);
	if (type != OBJ_MANIFEST)
		return -1;
	
	/* Read the manifest content */
	manifest_buffer = repo_read_object_file(r, manifest_oid, &type, &manifest_size);
	if (!manifest_buffer)
		return -1;
	
	/* Parse the manifest header using shared function */
	if (parse_manifest_header(manifest_buffer, manifest_size, &header) < 0) {
		free(manifest_buffer);
		return -1;
	}
	
	/* Collect chunk OIDs if requested */
	if (chunk_oids) {
		/* Initialize descriptor to iterate through chunk OIDs */
		init_manifest_desc(&desc, header.chunk_data, header.chunk_data_len, r->hash_algo);
		
		oid_array_clear(chunk_oids);
		while (manifest_entry(&desc)) {
			oid_array_append(chunk_oids, &desc.entry_oid);
		}
	}
	
	if (total_size)
		*total_size = header.total_size;
	
	free(manifest_buffer);
	return 0;
}

void *read_manifest_content(struct repository *r,
                           const struct object_id *manifest_oid,
                           unsigned long *size)
{
	struct manifest_stream *stream;
	unsigned long manifest_size;
	void *content;
	ssize_t bytes_read, total_read = 0;
	
	stream = open_manifest_stream(r, manifest_oid, &manifest_size);
	if (!stream)
		return NULL;
	
	content = xmalloc(manifest_size);
	while (total_read < manifest_size) {
		bytes_read = read_manifest_stream(stream, 
		                                  (char *)content + total_read,
		                                  manifest_size - total_read);
		if (bytes_read <= 0)
			break;
		total_read += bytes_read;
	}
	
	close_manifest_stream(stream);
	
	if (total_read == manifest_size) {
		*size = manifest_size;
		return content;
	}
	
	free(content);
	return NULL;
}

int get_manifest_size(struct repository *r,
                     const struct object_id *manifest_oid,
                     unsigned long *size)
{
	enum object_type type;
	unsigned long manifest_size;
	void *manifest_buffer;
	struct manifest_header header;
	
	/* Read the manifest object */
	manifest_buffer = odb_read_object(r->objects, manifest_oid, &type, &manifest_size);
	if (!manifest_buffer || type != OBJ_MANIFEST)
		return -1;
	
	/* Parse the header to get the total size */
	if (parse_manifest_header(manifest_buffer, manifest_size, &header) < 0) {
		free(manifest_buffer);
		return -1;
	}
	
	*size = header.total_size;
	free(manifest_buffer);
	return 0;
}