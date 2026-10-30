#pragma once

// Type-generic double-ended queue.
//
//     int *q = NULL;
//     dq_push_back_handle(q, 1);
//     dq_push_front_handle(q, 2);
//     printf("%d %d\n", dq_front(q), dq_back(q));
//     dq_free_handle(q);
//
// The pointer points at the element array. One metadata block lives directly
// before it, exactly like stb_ds's array header. The handle must be an lvalue
// variable; arguments are evaluated exactly once.
//
// Requires GNU C extensions.
//
// APIs whose name ends in `_handle` may replace the handle variable itself.
// They require a modifiable lvalue. All other APIs leave the handle alone.
//
// Allocation failure aborts the process.

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct DqHeader {
	size_t capacity;   // number of allocated slots
	size_t size;       // number of live elements
	size_t head;       // physical index of the first element
	// Keeps sizeof(DqHeader) a multiple of max_align_t, so the element array
	// that follows it is properly aligned. malloc itself is max_align_t aligned.
	max_align_t align_pad;
} DqHeader;

#define dq_header(a) ((DqHeader *)(a) - 1)

static inline const DqHeader *dq_const_header(const void *a) {
	return (const DqHeader *)a - 1;
}

// Physical index of logical element `i`. `i` must be less than the size.
static inline size_t dq_phys(const DqHeader *header, size_t i) {
	size_t index = header->head + i;
	if(index >= header->capacity) {
		index -= header->capacity;
	}
	return index;
}

// Grow the backing array so that it can hold `addlen` more elements. The
// elements are copied into logical order, which resets the head to zero.
static inline void *dq_growf(void *a, size_t elemsize, size_t addlen) {
	DqHeader *header = a != NULL ? dq_header(a) : NULL;
	size_t size = header != NULL ? header->size : 0;
	size_t capacity = header != NULL ? header->capacity : 0;
	size_t needed = size + addlen;

	if(needed < size) {   // overflow
		abort();
	}
	if(needed <= capacity) {
		return a;
	}

	size_t new_capacity = capacity != 0 ? capacity : 4;
	while(new_capacity < needed) {
		if(new_capacity > SIZE_MAX / 2) {
			new_capacity = needed;
			break;
		}
		new_capacity *= 2;
	}
	if(elemsize != 0 && new_capacity > (SIZE_MAX - sizeof(DqHeader)) / elemsize) {
		abort();
	}

	DqHeader *new_header = malloc(sizeof(DqHeader) + new_capacity * elemsize);
	if(new_header == NULL) {
		abort();
	}
	new_header->capacity = new_capacity;
	new_header->size = size;
	new_header->head = 0;

	if(header != NULL) {
		char *dst = (char *)(new_header + 1);
		const char *src = (const char *)a;
		for(size_t i = 0; i < size; ++i) {
			memcpy(dst + i * elemsize, src + dq_phys(header, i) * elemsize, elemsize);
		}
		free(header);
	}
	return new_header + 1;
}

static inline size_t dq_lenf(const void *a) {
	return a != NULL ? dq_const_header(a)->size : 0;
}

static inline size_t dq_capf(const void *a) {
	return a != NULL ? dq_const_header(a)->capacity : 0;
}

// Element access helpers. They return a pointer into the backing array; the
// public macros dereference it, which keeps dq_at() an lvalue.
static inline void *dq_atp(void *a, size_t elemsize, size_t i) {
	return (char *)a + dq_phys(dq_header(a), i) * elemsize;
}

static inline void *dq_frontp(void *a, size_t elemsize) {
	return (char *)a + dq_header(a)->head * elemsize;
}

static inline void *dq_backp(void *a, size_t elemsize) {
	DqHeader *header = dq_header(a);
	return (char *)a + dq_phys(header, header->size - 1) * elemsize;
}

static inline void *dq_push_backp(void *a, size_t elemsize) {
	DqHeader *header = dq_header(a);
	size_t index = dq_phys(header, header->size);
	++header->size;
	return (char *)a + index * elemsize;
}

static inline void *dq_push_frontp(void *a, size_t elemsize) {
	DqHeader *header = dq_header(a);
	header->head = header->head == 0 ? header->capacity - 1 : header->head - 1;
	++header->size;
	return (char *)a + header->head * elemsize;
}

static inline void *dq_pop_backp(void *a, size_t elemsize) {
	DqHeader *header = dq_header(a);
	size_t index = --header->size;
	return (char *)a + dq_phys(header, index) * elemsize;
}

static inline void *dq_pop_frontp(void *a, size_t elemsize) {
	DqHeader *header = dq_header(a);
	size_t index = header->head;
	header->head = index + 1 == header->capacity ? 0 : index + 1;
	--header->size;
	return (char *)a + index * elemsize;
}

// Grow to fit `n` total elements. May replace the handle.
#define dq_grow_handle(a, n)                          \
	({                                                \
		typeof(a) *dq_priv_ptr = &(a);                \
		*dq_priv_ptr = dq_growf(*dq_priv_ptr,         \
								sizeof **dq_priv_ptr, \
								(n));                 \
	})

#define dq_len(a) dq_lenf(a)
#define dq_cap(a) dq_capf(a)
#define dq_empty(a) (dq_lenf(a) == 0)

// Element access. The index must be in range.
#define dq_at(a, i) \
	(*(typeof(a))dq_atp((void *)(a), sizeof *(a), (i)))
#define dq_front(a) \
	(*(typeof(a))dq_frontp((void *)(a), sizeof *(a)))
#define dq_back(a) \
	(*(typeof(a))dq_backp((void *)(a), sizeof *(a)))

// Ensure room for at least `n` elements. Existing elements keep their order.
// May replace the handle.
#define dq_reserve_handle(a, n)                     \
	do {                                            \
		typeof(a) *dq_priv_ptr = &(a);              \
		size_t dq_priv_n = (n);                     \
		if(dq_priv_n > dq_lenf(*dq_priv_ptr)) {     \
			*dq_priv_ptr = dq_growf(                \
				*dq_priv_ptr,                       \
				sizeof **dq_priv_ptr,               \
				dq_priv_n - dq_lenf(*dq_priv_ptr)); \
		}                                           \
	} while(0)

// May replace the handle on growth.
#define dq_push_back_handle(a, v)                                       \
	({                                                                  \
		typeof(a) *dq_priv_ptr = &(a);                                  \
		*dq_priv_ptr = dq_growf(*dq_priv_ptr, sizeof **dq_priv_ptr, 1); \
		*(typeof(*dq_priv_ptr))dq_push_backp(                           \
			*dq_priv_ptr, sizeof **dq_priv_ptr) = (v);                  \
	})

// May replace the handle on growth.
#define dq_push_front_handle(a, v)                                      \
	({                                                                  \
		typeof(a) *dq_priv_ptr = &(a);                                  \
		*dq_priv_ptr = dq_growf(*dq_priv_ptr, sizeof **dq_priv_ptr, 1); \
		*(typeof(*dq_priv_ptr))dq_push_frontp(                          \
			*dq_priv_ptr, sizeof **dq_priv_ptr) = (v);                  \
	})

// The deque must not be empty.
#define dq_pop_back(a) \
	(*(typeof(a))dq_pop_backp((void *)(a), sizeof *(a)))
#define dq_pop_front(a) \
	(*(typeof(a))dq_pop_frontp((void *)(a), sizeof *(a)))

// Drop all elements but keep the storage.
#define dq_clear(a)                            \
	do {                                       \
		typeof(a) *dq_priv_ptr = &(a);         \
		if(*dq_priv_ptr != NULL) {             \
			dq_header(*dq_priv_ptr)->size = 0; \
			dq_header(*dq_priv_ptr)->head = 0; \
		}                                      \
	} while(0)

// Free the storage and set the handle to NULL.
#define dq_free_handle(a)                  \
	do {                                   \
		typeof(a) *dq_priv_ptr = &(a);     \
		if(*dq_priv_ptr != NULL) {         \
			free(dq_header(*dq_priv_ptr)); \
			*dq_priv_ptr = NULL;           \
		}                                  \
	} while(0)

// Iterate logical indices: combine with dq_at(a, i).
#define dq_foreach(a, i) for(size_t i = 0; i < dq_len(a); ++i)
