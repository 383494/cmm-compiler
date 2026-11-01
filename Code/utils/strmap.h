#pragma once

// String-keyed hash map: const char* -> void*.
//
//     StrMapEntry *m = NULL;
//     strmap_put_handle(m, "foo", ast);
//     BaseAST *a = strmap_get(m, "foo");
//     strmap_foreach(m, e) {
//         printf("%s\n", e->key);
//     }
//     strmap_free_handle(m);
//
// Keys are borrowed: the map stores the pointer and hashes/compares the
// string contents. The string must stay alive and unchanged for as long as
// the entry exists. Keys must not be NULL. Values may be NULL; use
// strmap_has() or strmap_getp() to distinguish a missing key from a NULL
// value.
//
// Entries are dense and in insertion order until a removal. Removal swaps
// the last entry into the removed slot. `m[i]` is valid for
// 0 <= i < strmap_len(m).
//
// The handle points at the entry array. One metadata block lives directly
// before it, and the bucket index is a separate allocation. The handle must
// be an lvalue variable; arguments are evaluated exactly once.
//
// APIs whose name ends in `_handle` may replace the handle variable itself.
// They require a modifiable lvalue. All other APIs leave the handle alone.
// Do not mutate the map while iterating it.
//
// Allocation failure aborts the process.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Keeps unused API functions quiet in translation units that include the
// header but use only part of it.
#if defined(__GNUC__) || defined(__clang__)
#	define STRMAP_UNUSED __attribute__((unused))
#else
#	define STRMAP_UNUSED
#endif

typedef struct StrMapEntry {
	const char *key;
	void *value;
} StrMapEntry;

typedef struct StrMapBucket {
	uint64_t hash;   // 0 = empty, 1 = tombstone, otherwise a live hash
	size_t index;    // entry index for a live bucket
} StrMapBucket;

typedef struct StrMapHeader {
	size_t size;           // number of live entries
	size_t capacity;       // number of allocated entries
	size_t bucket_count;   // power of two
	size_t used;           // live buckets
	size_t tombstones;     // deleted buckets
	StrMapBucket *buckets;
	// Keeps sizeof(StrMapHeader) a multiple of max_align_t, so the entry
	// array that follows it is properly aligned.
	max_align_t align_pad;
} StrMapHeader;

#define STRMAP_MIN_BUCKETS 8
#define STRMAP_MIN_CAPACITY 4

#define strmap_header(m) ((StrMapHeader *)(m) - 1)

static inline STRMAP_UNUSED const StrMapHeader *strmap_const_header(const void *m) {
	return (const StrMapHeader *)m - 1;
}

// FNV-1a followed by a 64-bit finalizer. Hash values 0 and 1 are reserved
// for empty and tombstone buckets.
static inline STRMAP_UNUSED uint64_t strmap_hash(const char *key) {
	uint64_t hash = UINT64_C(14695981039346656037);
	const unsigned char *p = (const unsigned char *)key;
	while(*p != 0) {
		hash ^= *p++;
		hash *= UINT64_C(1099511628211);
	}
	hash ^= hash >> 33;
	hash *= UINT64_C(0xff51afd7ed558ccd);
	hash ^= hash >> 33;
	if(hash < 2) {
		hash += 2;
	}
	return hash;
}

static inline STRMAP_UNUSED size_t strmap_len(const StrMapEntry *m) {
	return m != NULL ? strmap_const_header(m)->size : 0;
}

static inline STRMAP_UNUSED size_t strmap_cap(const StrMapEntry *m) {
	return m != NULL ? strmap_const_header(m)->capacity : 0;
}

static inline STRMAP_UNUSED bool strmap_empty(const StrMapEntry *m) {
	return strmap_len(m) == 0;
}

// Bucket slot holding `key`, or -1. The map must be non-NULL and have a
// non-empty bucket table.
static inline STRMAP_UNUSED ptrdiff_t strmap_find_bucket(const StrMapEntry *m,
														 const char *key,
														 uint64_t hash) {
	const StrMapHeader *h = strmap_const_header(m);
	size_t mask = h->bucket_count - 1;
	size_t slot = (size_t)hash & mask;
	for(size_t probe = 0; probe < h->bucket_count; ++probe) {
		const StrMapBucket *bucket = &h->buckets[slot];
		if(bucket->hash == 0) {
			return -1;
		}
		if(bucket->hash == hash && strcmp(m[bucket->index].key, key) == 0) {
			return (ptrdiff_t)slot;
		}
		slot = (slot + 1) & mask;
	}
	return -1;
}

// Slot to use for inserting `key`: the live slot if it already exists, else
// the first tombstone on the probe path, else the first empty slot. The
// table must have at least one empty slot.
static inline STRMAP_UNUSED size_t strmap_find_insert_slot(const StrMapEntry *m,
														   const char *key,
														   uint64_t hash,
														   bool *found) {
	const StrMapHeader *h = strmap_const_header(m);
	size_t mask = h->bucket_count - 1;
	size_t slot = (size_t)hash & mask;
	size_t tombstone = SIZE_MAX;
	for(size_t probe = 0; probe < h->bucket_count; ++probe) {
		const StrMapBucket *bucket = &h->buckets[slot];
		if(bucket->hash == 0) {
			*found = false;
			return tombstone != SIZE_MAX ? tombstone : slot;
		}
		if(bucket->hash == 1) {
			if(tombstone == SIZE_MAX) {
				tombstone = slot;
			}
		} else if(bucket->hash == hash && strcmp(m[bucket->index].key, key) == 0) {
			*found = true;
			return slot;
		}
		slot = (slot + 1) & mask;
	}
	abort();   // the load factor invariant guarantees an empty slot
}

// Rebuild the bucket table at `new_count` slots, which must be a power of two.
static inline STRMAP_UNUSED void strmap_rehash(StrMapHeader *h, size_t new_count) {
	if(new_count < STRMAP_MIN_BUCKETS) {
		new_count = STRMAP_MIN_BUCKETS;
	}
	if((new_count & (new_count - 1)) != 0) {
		abort();
	}
	if(new_count > SIZE_MAX / sizeof(StrMapBucket)) {
		abort();
	}
	StrMapBucket *buckets = calloc(new_count, sizeof *buckets);
	if(buckets == NULL) {
		abort();
	}

	StrMapBucket *old = h->buckets;
	h->buckets = buckets;
	h->bucket_count = new_count;
	h->used = 0;
	h->tombstones = 0;

	StrMapEntry *m = (StrMapEntry *)(h + 1);
	size_t mask = new_count - 1;
	for(size_t i = 0; i < h->size; ++i) {
		uint64_t hash = strmap_hash(m[i].key);
		size_t slot = (size_t)hash & mask;
		while(buckets[slot].hash != 0) {
			slot = (slot + 1) & mask;
		}
		buckets[slot].hash = hash;
		buckets[slot].index = i;
		++h->used;
	}
	free(old);
}

// Ensure the bucket table can hold `add` more entries at a load of at most
// 3/4, rebuilding it in place first if tombstones account for the pressure.
static inline STRMAP_UNUSED void strmap_buckets_reserve(StrMapHeader *h, size_t add) {
	size_t occupied = h->used + h->tombstones;
	if(occupied < h->used || add > SIZE_MAX - occupied) {
		abort();
	}
	occupied += add;
	if(h->bucket_count != 0 &&
	   occupied <= h->bucket_count - h->bucket_count / 4) {
		return;
	}

	size_t needed = h->used;
	if(add > SIZE_MAX - needed) {
		abort();
	}
	needed += add;

	size_t count = h->bucket_count != 0 ? h->bucket_count : STRMAP_MIN_BUCKETS;
	while(needed > count - count / 4) {
		if(count > SIZE_MAX / 2) {
			abort();
		}
		count *= 2;
	}
	strmap_rehash(h, count);
}

// Grow the entry array to hold at least `min_capacity` entries.
static inline STRMAP_UNUSED StrMapEntry *strmap_entries_reserve(StrMapEntry *m,
																size_t min_capacity) {
	StrMapHeader *h = m != NULL ? strmap_header(m) : NULL;
	size_t capacity = h != NULL ? h->capacity : 0;
	if(capacity >= min_capacity) {
		return m;
	}

	size_t new_capacity = capacity != 0 ? capacity : STRMAP_MIN_CAPACITY;
	while(new_capacity < min_capacity) {
		if(new_capacity > SIZE_MAX / 2) {
			new_capacity = min_capacity;
			break;
		}
		new_capacity *= 2;
	}
	if(new_capacity > (SIZE_MAX - sizeof(StrMapHeader)) / sizeof(StrMapEntry)) {
		abort();
	}

	size_t bytes = sizeof(StrMapHeader) + new_capacity * sizeof(StrMapEntry);
	StrMapHeader *new_header;
	if(h == NULL) {
		new_header = calloc(1, bytes);
		if(new_header == NULL) {
			abort();
		}
		new_header->capacity = new_capacity;
	} else {
		new_header = realloc(h, bytes);
		if(new_header == NULL) {
			abort();
		}
		// Zero the newly added slots so every entry is initialized even
		// before it is written.
		char *first_new = (char *)(new_header + 1) +
						  capacity * sizeof(StrMapEntry);
		memset(first_new, 0, (new_capacity - capacity) * sizeof(StrMapEntry));
		new_header->capacity = new_capacity;
	}
	return (StrMapEntry *)(new_header + 1);
}

// Entry index for `key`, or -1.
static inline STRMAP_UNUSED ptrdiff_t strmap_geti(const StrMapEntry *m, const char *key) {
	if(m == NULL || key == NULL) {
		return -1;
	}
	const StrMapHeader *h = strmap_const_header(m);
	if(h->bucket_count == 0) {
		return -1;
	}
	ptrdiff_t slot = strmap_find_bucket(m, key, strmap_hash(key));
	return slot < 0 ? -1 : (ptrdiff_t)h->buckets[slot].index;
}

static inline STRMAP_UNUSED void *strmap_get(const StrMapEntry *m, const char *key) {
	ptrdiff_t index = strmap_geti(m, key);
	return index < 0 ? NULL : m[index].value;
}

static inline STRMAP_UNUSED StrMapEntry *strmap_getp(StrMapEntry *m, const char *key) {
	ptrdiff_t index = strmap_geti(m, key);
	return index < 0 ? NULL : &m[index];
}

static inline STRMAP_UNUSED bool strmap_has(const StrMapEntry *m, const char *key) {
	return strmap_geti(m, key) >= 0;
}

// Private: insert or update, possibly replacing the handle. Returns the
// entry. `key` must not be NULL.
static inline STRMAP_UNUSED StrMapEntry *strmap_putf(StrMapEntry **mp,
													 const char *key,
													 void *value) {
	if(key == NULL) {
		abort();
	}
	StrMapEntry *m = *mp;
	uint64_t hash = strmap_hash(key);

	// Update in place without touching the table shape.
	if(m != NULL) {
		const StrMapHeader *h = strmap_const_header(m);
		if(h->bucket_count != 0) {
			ptrdiff_t slot = strmap_find_bucket(m, key, hash);
			if(slot >= 0) {
				size_t index = h->buckets[slot].index;
				m[index].value = value;
				return &m[index];
			}
		}
	}

	size_t size = m != NULL ? strmap_const_header(m)->size : 0;
	if(size == SIZE_MAX) {
		abort();
	}
	m = strmap_entries_reserve(m, size + 1);
	StrMapHeader *h = strmap_header(m);
	strmap_buckets_reserve(h, 1);

	bool found;
	size_t slot = strmap_find_insert_slot(m, key, hash, &found);
	size_t index;
	if(found) {
		index = h->buckets[slot].index;
		m[index].value = value;
	} else {
		index = h->size;
		m[index].key = key;
		m[index].value = value;
		if(h->buckets[slot].hash == 1) {
			--h->tombstones;
		}
		h->buckets[slot].hash = hash;
		h->buckets[slot].index = index;
		++h->used;
		++h->size;
	}
	*mp = m;
	return &m[index];
}

// Remove `key`. Returns 1 if it was present, else 0. Removal may rebuild the
// bucket table, but it never moves the handle.
static inline STRMAP_UNUSED int strmap_remove(StrMapEntry *m, const char *key) {
	if(m == NULL || key == NULL) {
		return 0;
	}
	StrMapHeader *h = strmap_header(m);
	if(h->bucket_count == 0) {
		return 0;
	}
	ptrdiff_t slot = strmap_find_bucket(m, key, strmap_hash(key));
	if(slot < 0) {
		return 0;
	}

	size_t index = h->buckets[slot].index;
	size_t last = h->size - 1;
	h->buckets[slot].hash = 1;
	h->buckets[slot].index = SIZE_MAX;
	--h->used;
	++h->tombstones;

	if(index != last) {
		m[index] = m[last];
		ptrdiff_t moved = strmap_find_bucket(m, m[index].key, strmap_hash(m[index].key));
		if(moved < 0) {
			abort();   // the moved entry must still be indexed
		}
		h->buckets[moved].index = index;
	}
	h->size = last;

	if(h->tombstones > h->used && h->tombstones > STRMAP_MIN_BUCKETS) {
		strmap_rehash(h, h->bucket_count);
	}
	return 1;
}

// Private: reserve entry and bucket capacity for `n` total entries.
static inline STRMAP_UNUSED StrMapEntry *strmap_reservef(StrMapEntry **mp, size_t n) {
	if(n == 0) {
		return *mp;
	}
	StrMapEntry *m = strmap_entries_reserve(*mp, n);
	StrMapHeader *h = strmap_header(m);
	if(n > h->size) {
		strmap_buckets_reserve(h, n - h->size);
	}
	*mp = m;
	return m;
}

// Drop all entries but keep the storage.
static inline STRMAP_UNUSED void strmap_clear(StrMapEntry *m) {
	if(m == NULL) {
		return;
	}
	StrMapHeader *h = strmap_header(m);
	if(h->bucket_count != 0) {
		memset(h->buckets, 0, h->bucket_count * sizeof *h->buckets);
	}
	h->size = 0;
	h->used = 0;
	h->tombstones = 0;
}

// Private: free the map. The handle must be replaced with NULL by the caller.
static inline STRMAP_UNUSED void strmap_freef(StrMapEntry *m) {
	if(m == NULL) {
		return;
	}
	StrMapHeader *h = strmap_header(m);
	free(h->buckets);
	free(h);
}

// May replace the handle. Returns the entry.
#define strmap_put_handle(m, k, v) strmap_putf(&(m), (k), (v))

// Ensure room for `n` total entries. May replace the handle.
#define strmap_reserve_handle(m, n)                               \
	do {                                                          \
		typeof(m) *strmap_priv_ptr = &(m);                        \
		*strmap_priv_ptr = strmap_reservef(strmap_priv_ptr, (n)); \
	} while(0)

// Free the storage and set the handle to NULL.
#define strmap_free_handle(m)              \
	do {                                   \
		typeof(m) *strmap_priv_ptr = &(m); \
		strmap_freef(*strmap_priv_ptr);    \
		*strmap_priv_ptr = NULL;           \
	} while(0)

// Iterate live entries of `m` as `StrMapEntry *e`. The map must not be
// mutated during the loop.
#define strmap_foreach(m, e)                                                                                                                                                    \
	for(StrMapEntry *strmap_priv_map = (m), *e = strmap_priv_map, *strmap_priv_end = strmap_priv_map != NULL ? strmap_priv_map + strmap_len(strmap_priv_map) : strmap_priv_map; \
		e != NULL && e < strmap_priv_end;                                                                                                                                       \
		++e)
