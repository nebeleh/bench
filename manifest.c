#include "git-compat-util.h"
#include "manifest.h"
#include "object-file.h"
#include "repository.h"
#include "alloc.h"
#include "hex.h"
#include "strbuf.h"
#include "hash.h"

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

struct manifest *create_manifest(struct repository *r, const struct object_id *chunk_oids, size_t chunk_count)
{
	struct strbuf buf = STRBUF_INIT;
	struct object_id manifest_oid;
	struct manifest *manifest;
	size_t i;

	/* Build manifest content */
	for (i = 0; i < chunk_count; i++) {
		strbuf_addstr(&buf, oid_to_hex(&chunk_oids[i]));
		strbuf_addch(&buf, '\n');
	}

	/* Write manifest object */
	if (write_object_file(buf.buf, buf.len, OBJ_MANIFEST, &manifest_oid) < 0) {
		strbuf_release(&buf);
		return NULL;
	}

	strbuf_release(&buf);

	/* Create and return manifest struct */
	manifest = lookup_manifest(r, &manifest_oid);
	if (!manifest)
		return NULL;

	/*
	 * We don't need to store anything extra - the manifest
	 * content is already in the object database and will be
	 * loaded when needed via parse_manifest_buffer().
	 */
	manifest->object.parsed = 1;

	return manifest;
}

void free_manifest(struct manifest *m)
{
	if (!m)
		return;
	FREE_AND_NULL(m->buffer);
	m->size = 0;
}