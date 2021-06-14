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

  /// The number of elements in the array.
  int64_t count;

  /// The capacity of the array's storage, in bytes.
  int64_t capacity;

  /// A pointer to the array's reference counter.
  int64_t* refcount;

  /// A pointer to the array's storage.
  void* storage;

} mvs_AnyArray;

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
  array->count = count;
  array->refcount = malloc(sizeof(int64_t));
  *(array->refcount) = 1;

  if (count > 0) {
    array->capacity = count * size;
    array->storage = malloc(array->capacity);
#ifdef DEBUG
    fprintf(stderr, "  alloc %lli bytes at %p\n", count * size, array->storage);
#endif
    if (elem_type->init != NULL) {
      for (size_t i = 0; i < count; ++i) {
        elem_type->init(&array->storage[i * size]);
      }
    } else {
      memset(array->storage, 0, count * size);
    }
  } else {
    array->capacity = 0;
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

  if (*(array->refcount) > 1) {
#ifdef DEBUG
    fprintf(stderr, "  release %p\n", array->storage);
#endif
    *(array->refcount) = 1;
    return;
  }

  if (elem_type->drop != NULL) {
    for (size_t i = 0; i < array->count; ++i) {
      elem_type->drop(&array->storage[i * elem_type->size]);
    }
  }

#ifdef DEBUG
  fprintf(stderr, "  dealloc %p\n", array->storage);
#endif

  free(array->refcount);
  free(array->storage);
  memset(array, 0, sizeof(mvs_AnyArray));
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
  if (*(array->refcount) <= 1) { return; }

  // Allocate a new storage.
  void* unique_storage = malloc(array->capacity);
#ifdef DEBUG
    fprintf(stderr, "  alloc %lli bytes at %p\n", array->capacity, unique_storage);
#endif

  // Copy the contents of the current storage.
  if (elem_type->copy == NULL) {
    memcpy(unique_storage, array->storage, array->capacity);
  } else {
    for (size_t i = 0; i < array->count; ++i) {
      elem_type->copy(&unique_storage[i * elem_type->size],
                      &array->storage[i * elem_type->size]);
    }
  }

  // Decrement the reference counter on the old storage.
  *(array->refcount) -= 1;

  // Substitute the old array's storage.
  array->refcount = malloc(sizeof(int64_t));
  *(array->refcount) = 1;
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
  if (lhs->count == rhs->count) {
    for (int64_t i = 0; i < lhs->count; ++i) {
      void* a = &lhs->storage[i * elem_type->size];
      void* b = &rhs->storage[i * elem_type->size];
      if (elem_type->equal(a, b) == 0) {
        return 0;
      }
    }
    return 1;
  } else {
    return 0;
  }
}

void mvs_print_i64(int64_t value) {
  printf("%lli\n", value);
}

void mvs_print_f64(double value) {
  printf("%f\n", value);
}

double mvs_uptime_nanoseconds() {
  struct timespec spec;
  if (clock_gettime(CLOCK_REALTIME, &spec) == -1) {
    return 0;
  }
  return spec.tv_sec * 1000000000L + spec.tv_nsec;
}
