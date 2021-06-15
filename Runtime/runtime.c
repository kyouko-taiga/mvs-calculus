#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/// A metatype.
typedef struct {

  /// The size (a.k.a. stride) of the type.
  const int64_t size;

  /// The type-erased zero-inititiazer for instances of the type.
  ///
  /// If `NULL`, then instances of the type are considered "trivial".
  const void (*init)(void*);

  /// The type-erased destructor for instances of the type.
  ///
  /// If `NULL`, then instances of the type are considered "trivial".
  const void (*drop)(void*);

  /// The type-erased copy function for instances of the type.
  ///
  /// If `NULL`, then instances of the type are considered "trivial".
  const void (*copy)(void*, void*);

  /// The type-erased equality function for instances of the type.
  const int64_t (*equal)(void*, void*);

} mvs_MetaType;

/// A type-erased array.
typedef struct {

  /// A pointer to the array's storage.
  ///
  /// The storage has the following layout:
  ///
  ///     { refcount: i64; count: i64; capacity: i64; elements: T[capacity] }
  ///
  /// If the pointer is null, then it is assumed that the array has a 0 capacity.
  void* storage;

} mvs_AnyArray;

#define ARRAY_HEADER ((int64_t)sizeof(int64_t) * 3)

void* mvs_malloc(int64_t size) {
  void* buf = malloc(size);
  memset(buf, 0, size);
  return buf;
}

void mvs_free(void* ptr) {
  free(ptr);
}

void mvs_array_init(mvs_AnyArray* array,
                    const mvs_MetaType* elem_type,
                    int64_t count,
                    int64_t size) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_init(%p, %p, %lli, %lli)\n", array, elem_type, count, size);
#endif

  if (count > 0) {
    // Allocate new storage.
    int64_t capacity = count * size;
    array->storage = malloc(ARRAY_HEADER + capacity);
#ifdef DEBUG
    fprintf(stderr, "  alloc %lli+%lli bytes at %p\n", ARRAY_HEADER, capacity, array->storage);
#endif

    // Configure the storage's header.
    int64_t* header = (int64_t*)array->storage;
    header[0] = 1;
    header[1] = count;
    header[2] = capacity;

    // Initialize the storage's payload.
    void* payload = array->storage + ARRAY_HEADER;
    if (elem_type->init != NULL) {
      for (size_t i = 0; i < count; ++i) {
        elem_type->init(&payload[i * size]);
      }
    } else {
      memset(payload, 0, count * size);
    }
  } else {
    array->storage = NULL;
  }
}

/// Deinitializes `array`, deallocating memory as necessary.
///
/// - Parameters:
///   - array: A pointer to the array that should be deinitialized.
///   - elem_type: A pointer to the metatype of the type of the array's elements.
void mvs_array_drop(mvs_AnyArray* array, const mvs_MetaType* elem_type) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_drop(%p, %p)\n", array, elem_type);
#endif

  int64_t* header = (int64_t*)array->storage;
  if ((header != NULL) && (header[0] > 1)) {
    header[0] -= 1;
#ifdef DEBUG
    fprintf(stderr, "  release %p (%lli)\n", array->storage, header[0]);
#endif
    return;
  }

  if (elem_type->drop != NULL) {
    void* payload = array->storage + ARRAY_HEADER;
    for (size_t i = 0; i < header[1]; ++i) {
      elem_type->drop(&payload[i * elem_type->size]);
    }
  }

#ifdef DEBUG
  fprintf(stderr, "  dealloc %p\n", array->storage);
#endif

  free(array->storage);
  array->storage = NULL;
}

void mvs_array_copy(mvs_AnyArray* dst, mvs_AnyArray* src) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_copy(%p, %p)\n", dst, src);
#endif

  // Trivial if the right hand side is null.
  dst->storage = src->storage;
  if (src->storage != NULL) {
    *((int64_t*)src->storage) += 1;
#ifdef DEBUG
    fprintf(stderr, "  retain  %p (%lli)\n", src->storage, *((int64_t*)src->storage));
#endif
  }
}

/// Creates a unique copy of `array`'s storage.
///
/// - Parameters:
///   - array: A pointer to the array to uniquify.
///   - elem_type: A pointer to the metatype of the type of the array's elements.
void mvs_array_uniq(mvs_AnyArray* array, const mvs_MetaType* elem_type) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_uniq(%p, %p)\n", array, elem_type);
#endif

  // Nothing to do if the array's already unique.
  int64_t* header = (int64_t*)array->storage;
  if ((header == NULL) || (header[0] <= 1)) { return; }

  // Allocate a new storage.
  void* unique_storage = malloc(ARRAY_HEADER + header[2]);
#ifdef DEBUG
  fprintf(stderr, "  alloc %lli+%lli bytes at %p\n", ARRAY_HEADER, header[2], unique_storage);
#endif

  // Copy the contents of the current storage.
  if (elem_type->copy == NULL) {
    memcpy(unique_storage, array->storage, ARRAY_HEADER + header[2]);
  } else {
    void* src = array->storage + ARRAY_HEADER;
    void* dst = unique_storage + ARRAY_HEADER;
    for (size_t i = 0; i < header[1]; ++i) {
      elem_type->copy(&dst[i * elem_type->size], &src[i * elem_type->size]);
    }
  }

  // Decrement the reference counter on the old storage.
  header[0] -= 1;

  // Substitute the old array's storage.
  int64_t* new_header = (int64_t*)unique_storage;
  new_header[0] = 1;
  array->storage = unique_storage;
}

/// Returns whether the two given arrays are equal, assuming they are of the same type.
///
/// - Parameters:
///   - lhs: An array.
///   - rhs: Another array.
///   - elem_type: A pointer to the metatype of the type of the array's elements.
int64_t mvs_array_equal(const mvs_AnyArray* lhs,
                        const mvs_AnyArray* rhs,
                        const mvs_MetaType* elem_type)
{
  // Trivial if the arrays point to the same storage.
  if (lhs->storage == rhs->storage) { return 1; }

  // Check for element-wise equality.
  int64_t* lhs_header = (int64_t*)lhs->storage;
  int64_t* rhs_header = (int64_t*)rhs->storage;
  if (lhs_header[1] != rhs_header[1]) {
    return 0;
  }

  void* lhs_payload = lhs->storage + ARRAY_HEADER;
  void* rhs_payload = rhs->storage + ARRAY_HEADER;
  for (int64_t i = 0; i < lhs_header[1]; ++i) {
    void* a = &lhs_payload[i * elem_type->size];
    void* b = &rhs_payload[i * elem_type->size];
    if (elem_type->equal(a, b) == 0) {
      return 0;
    }
  }
  return 1;
}

void mvs_print_i64(int64_t value) {
  printf("%lli\n", value);
}

void mvs_print_f64(double value) {
  printf("%f\n", value);
}
