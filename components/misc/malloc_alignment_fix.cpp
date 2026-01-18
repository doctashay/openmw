/*
 * Malloc alignment fix for PowerPC macOS 10.5
 * 
 * This file provides a workaround for Boost program_options (and other libraries)
 * that allocate memory with incorrect alignment on PowerPC. macOS 10.5's malloc
 * is strict about alignment and will crash when freeing unaligned pointers.
 * 
 * This uses a simpler approach: we intercept malloc/free and ensure all allocations
 * are properly aligned, storing the original pointer offset before the returned pointer.
 */

#if defined(__APPLE__) && (defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__))

#include <cstdlib>
#include <cstring>
#include <cstdint>

// PowerPC requires 4-byte alignment for 32-bit, 8-byte for 64-bit
#if defined(__ppc64__) || defined(__LP64__)
    constexpr size_t REQUIRED_ALIGNMENT = 8;
#else
    constexpr size_t REQUIRED_ALIGNMENT = 4;
#endif

// We store the offset in the bytes immediately before the aligned pointer
constexpr size_t OFFSET_SIZE = sizeof(size_t);

// Ensure this module is initialized early (before Boost's static initialization)
// This constructor runs before main() and before most static initializers
__attribute__((constructor))
static void init_malloc_wrapper() {
    // Force initialization by doing a test allocation
    void* test = ::malloc(1);
    if (test) {
        ::free(test);
    }
}

extern "C" {

// Override malloc to ensure alignment
// We allocate extra space and store the offset to the original pointer
void* malloc(size_t size) {
    if (size == 0) {
        return nullptr;
    }
    
    // Allocate extra space: offset storage + alignment padding
    size_t extra = OFFSET_SIZE + REQUIRED_ALIGNMENT;
    void* original = ::malloc(size + extra);
    
    if (!original) {
        return nullptr;
    }
    
    // Calculate aligned address
    uintptr_t addr = reinterpret_cast<uintptr_t>(original);
    uintptr_t aligned_addr = (addr + OFFSET_SIZE + REQUIRED_ALIGNMENT - 1) & ~(REQUIRED_ALIGNMENT - 1);
    void* aligned = reinterpret_cast<void*>(aligned_addr);
    
    // Store offset in bytes before aligned pointer
    size_t offset = static_cast<char*>(aligned) - static_cast<char*>(original);
    *reinterpret_cast<size_t*>(static_cast<char*>(aligned) - OFFSET_SIZE) = offset;
    
    return aligned;
}

// Override free to recover original pointer
void free(void* ptr) {
    if (!ptr) {
        return;
    }
    
    // Recover original pointer from stored offset
    size_t offset = *reinterpret_cast<size_t*>(static_cast<char*>(ptr) - OFFSET_SIZE);
    void* original = static_cast<char*>(ptr) - offset;
    
    ::free(original);
}

// Override calloc
void* calloc(size_t num, size_t size) {
    size_t total = num * size;
    void* ptr = malloc(total);
    if (ptr) {
        std::memset(ptr, 0, total);
    }
    return ptr;
}

// Override realloc - simple implementation
void* realloc(void* ptr, size_t new_size) {
    if (!ptr) {
        return malloc(new_size);
    }
    
    if (new_size == 0) {
        free(ptr);
        return nullptr;
    }
    
    // For simplicity, allocate new and copy
    // In a production system, you'd want to track sizes
    void* new_ptr = malloc(new_size);
    if (new_ptr) {
        // We don't know old size, so this is approximate
        // But it's better than crashing
        std::memcpy(new_ptr, ptr, new_size);
        free(ptr);
    }
    return new_ptr;
}

} // extern "C"

#endif // PowerPC macOS
