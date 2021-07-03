#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {

/// A metatype.
struct mvs_MetaType {

  /// The size (a.k.a. stride) of the type.
  const int64_t size;

  /// The type-erased zero-inititiazer for instances of the type.
  ///
  /// If null, then instances of the type are considered "trivial".
  const void (*init)(void*);

  /// The type-erased destructor for instances of the type.
  ///
  /// If null, then instances of the type are considered "trivial".
  const void (*drop)(void*);

  /// The type-erased copy function for instances of the type.
  ///
  /// If null, then instances of the type are considered "trivial".
  const void (*copy)(void*, void*);

  /// The type-erased equality function for instances of the type.
  const int64_t (*equal)(void*, void*);

};

/// A type-erased array.
struct mvs_AnyArray {

  /// A pointer to the array's payload.
  ///
  /// The storage of an array is a contiguous block of memory with the following layout:
  ///
  ///     { header: ArrayHeader; payload: T[header.count] }
  ///
  /// This field is a pointer to the base address of the payload, i.e., it is the address of the
  /// array's storage offset by `sizeof(ArrayHeader)`.
  ///
  /// If the pointer is null, then it is assumed that the array has a 0 capacity.
  void* payload;

};

}

/// The header of an array.
struct ArrayHeader {

  /// The number of references to the array's storage.
  std::atomic<uint64_t> refc;

  /// The number of elements in the array.
  int64_t count;

  /// The capacity of the array's payload, in bytes.
  int64_t capacity;

};

/// Returns a pointer to the header of the given array.
///
/// - Parameter array: A pointer to an initialized array structure.
inline ArrayHeader* get_array_header(mvs_AnyArray* array) {
  if (array->payload == nullptr) { return nullptr; }
  return (ArrayHeader*)((uint8_t*)array->payload - sizeof(ArrayHeader));
}

extern "C" {

void* mvs_malloc(int64_t size) {
  return malloc(size);
}

void mvs_free(void* ptr) {
  free(ptr);
}

/// Initializes an array structure.
///
/// - Parameters:
///   - array: A pointer an uninitialized array structure.
///   - elem_type: A pointer to the metatype of the type of the array's elements.
///   - count: The number of elements in the array.
///   - size: The size of each element, in bytes.
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
    auto* storage = malloc(sizeof(ArrayHeader) + capacity);
    array->payload = (uint8_t*)storage + sizeof(ArrayHeader);

#ifdef DEBUG
    fprintf(stderr, "  alloc %lu+%lli bytes at %p\n", sizeof(ArrayHeader), capacity, storage);
#endif

    // Configure the storage's header.
    ArrayHeader* header = (ArrayHeader*)storage;
    header->refc     = 1;
    header->count    = count;
    header->capacity = capacity;

    // Initialize the storage's payload.
    uint8_t* payload = (uint8_t*)array->payload;
    if (elem_type->init != nullptr) {
      for (size_t i = 0; i < count; ++i) {
        elem_type->init(&payload[i * size]);
      }
    } else {
      memset(payload, 0, capacity);
    }
  } else {
    array->payload = nullptr;
  }
}

/// Destroys an array reference, deallocating memory as necessary.
///
/// - Parameters:
///   - array: A pointer to the array that should be destroyed.
///   - elem_type: A pointer to the metatype of the type of the array's elements.
void mvs_array_drop(mvs_AnyArray* array, const mvs_MetaType* elem_type) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_drop(%p, %p)\n", array, elem_type);
#endif

  // Bail out if the array storage is not allocated.
  auto* header = get_array_header(array);
  if (header == nullptr) { return; }

  // Decrement the reference counter.
  auto value = header->refc.fetch_sub(1, std::memory_order_acq_rel);

  // If the reference counter didn't reach zero, we're done.
  if (value != 1) {
#ifdef DEBUG
    fprintf(stderr, "  release %p (%lli)\n", header, value - 1);
#endif
    return;
  }

  // If the reference counter reached zero, we must deallocate the storage.
  if (elem_type->drop != nullptr) {
    uint8_t* payload = (uint8_t*)array->payload;
    for (size_t i = 0; i < header->count; ++i) {
      elem_type->drop(&payload[i * elem_type->size]);
    }
  }

#ifdef DEBUG
  fprintf(stderr, "  dealloc %p\n", header);
#endif

  free(header);
  array->payload = nullptr;
}

/// Copies an array.
///
/// - Parameters:
///   - dst: A pointer to the destination array.
///   - src: A pointer to the source array.
void mvs_array_copy(mvs_AnyArray* dst, mvs_AnyArray* src) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_copy(%p, %p)\n", dst, src);
#endif

  // Copy the array reference.
  *dst = *src;

  // Increment the reference counter.
  auto* header = get_array_header(src);
  if (header == nullptr) { return; }

  auto value = header->refc.fetch_add(1, std::memory_order_relaxed);
#ifdef DEBUG
  fprintf(stderr, "  retain  %p (%lli)\n", header, value + 1);
#endif
}

/// Guarantees that the given array structure has a unique storage.
///
/// - Parameters:
///   - array: A pointer to the array to uniquify.
///   - elem_type: A pointer to the metatype of the type of the array's elements.
void mvs_array_uniq(mvs_AnyArray* array, const mvs_MetaType* elem_type) {
#ifdef DEBUG
  fprintf(stderr, "mvs_array_uniq(%p, %p)\n", array, elem_type);
#endif

  // If the array's already unique, we're done.
  auto* header = get_array_header(array);
  if ((header == nullptr) || (header->refc.load(std::memory_order_acquire) == 1)) { return; }

  // Allocate a new storage.
  void* unique_storage = malloc(sizeof(ArrayHeader) + header->capacity);
#ifdef DEBUG
  fprintf(stderr, "  alloc %lu+%lli bytes at %p\n", sizeof(ArrayHeader), header->capacity, unique_storage);
#endif

  // Copy the contents of the current storage.
  if (elem_type->copy == NULL) {
    memcpy(unique_storage, header, sizeof(ArrayHeader) + header->capacity);
  } else {
    uint8_t* src = (uint8_t*)array->payload;
    uint8_t* dst = (uint8_t*)unique_storage + sizeof(ArrayHeader);
    for (size_t i = 0; i < header->count; ++i) {
      elem_type->copy(&dst[i * elem_type->size], &src[i * elem_type->size]);
    }
  }

  // Decrement the reference counter on the old storage.
  header->refc.fetch_sub(1, std::memory_order_acq_rel);

  // Substitute the old array's storage.
  ArrayHeader* new_header = (ArrayHeader*)unique_storage;
  new_header->refc = 1;
  array->payload = (uint8_t*)unique_storage + sizeof(ArrayHeader);
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
  if (lhs->payload == rhs->payload) { return 1; }

  // Check for element-wise equality.
  auto* lhs_header = get_array_header(const_cast<mvs_AnyArray*>(lhs));
  auto* rhs_header = get_array_header(const_cast<mvs_AnyArray*>(rhs));
  if (lhs_header->count != rhs_header->count) {
    return 0;
  }

  uint8_t* lhs_payload = (uint8_t*)lhs->payload;
  uint8_t* rhs_payload = (uint8_t*)rhs->payload;
  for (int64_t i = 0; i < lhs_header->count; ++i) {
    void* a = &lhs_payload[i * elem_type->size];
    void* b = &rhs_payload[i * elem_type->size];
    if (elem_type->equal(a, b) == 0) {
      return 0;
    }
  }
  return 1;
}

/// Returns the number of nanoseconds since boot, excluding any time the system spent asleep.
double mvs_uptime_nanoseconds() {
  auto clock = std::chrono::high_resolution_clock::now();
  auto delta = std::chrono::duration_cast<std::chrono::nanoseconds>(clock.time_since_epoch());
  return delta.count();
}

void mvs_print_i64(int64_t value) {
  printf("%lli\n", value);
}

void mvs_print_f64(double value) {
  printf("%f\n", value);
}

}
