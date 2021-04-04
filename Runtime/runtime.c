#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/// A metatype.
typedef struct {
  /// The name of the type.
  const char* name;
  /// The size (a.k.a. stride) of the type.
  const int64_t size;
  /// The type-erased zero-inititiazer for instances of the type.
  const void (*init)(void*);
  /// The type-erased destructor for instances of the type.
  const void (*drop)(void*);
  /// The type-erased copy function for instances of the type.
  const void (*copy)(void*, void*);
} mvs_MetaType;

/// A type-erased array.
typedef struct {
  /// The number of elements in the array.
  int64_t count;
  /// The capacity of the array's storage, in bytes.
  int64_t capacity;
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
  if (count > 0) {
    array->capacity = count * size;
    array->storage = malloc(array->capacity);
#ifdef DEBUG
    fprintf(stderr, "  alloc %lli bytes at %p\n", count * size, array->storage);
#endif
    if ((elem_type != NULL) && (elem_type->init != NULL)) {
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
///   - elem_type: A pointer to the metatype of the type of the array's elements. If `NULL`, then
///     the elements are considered of a trivial type.
void mvs_array_drop(mvs_AnyArray* array, const mvs_MetaType* elem_type) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_drop(%p, %p)\n", array, elem_type);
#endif
  if ((elem_type != NULL) && (elem_type->drop != NULL)) {
    for (size_t i = 0; i < array->count; ++i) {
      elem_type->drop(&array->storage[i * elem_type->size]);
    }
  }

  array->count = 0;
  array->capacity = 0;
#ifdef DEBUG
  fprintf(stderr, "  dealloc %p\n", array->storage);
#endif
  free(array->storage);
  array->storage = NULL;
}

/// Copies `array_src` into `array_dst`.
///
/// - Parameters:
///   - array_dst: A pointer to the destination array.
///   - array_src: A pointer to the source array.
///   - elem_type: A pointer to the metatype of the type of the array's elements. If `NULL`, then
///     the elements are considered of a trivial type.
void mvs_array_copy(mvs_AnyArray* array_dst,
                    const mvs_AnyArray* array_src,
                    const mvs_MetaType* elem_type) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_copy(%p, %p, %p)\n", array_dst, array_src, elem_type);
#endif
  if ((elem_type != NULL) && (elem_type->drop != NULL)) {
    for (size_t i = 0; i < array_dst->count; ++i) {
      elem_type->drop(&array_dst->storage[i * elem_type->size]);
    }
  }

  if (array_dst->capacity < array_src->capacity) {
    free(array_dst->storage);
    array_dst->capacity = array_src->capacity;
    array_dst->storage = malloc(array_src->capacity);
  }

  array_dst->count = array_src->count;
  if (elem_type == NULL) {
    memcpy(array_dst->storage, array_src->storage, array_src->capacity);
  } else {
    for (size_t i = 0; i < array_src->count; ++i) {
      elem_type->copy(&array_dst->storage[i * elem_type->size],
                      &array_src->storage[i * elem_type->size]);
    }
  }
}

void mvs_print_i64(int64_t value) {
  printf("%lli\n", value);
}

void mvs_print_f64(double value) {
  printf("%f\n", value);
}
