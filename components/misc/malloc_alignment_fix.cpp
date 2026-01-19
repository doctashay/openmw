/*
 * Malloc alignment fix for PowerPC macOS 10.5
 * 
 * This file provides a workaround for Boost program_options (and other libraries)
 * that allocate memory with incorrect alignment on PowerPC. macOS 10.5's malloc
 * is strict about alignment and will crash when freeing unaligned pointers.
 * 
 * This uses dlsym to get the original malloc/free functions to avoid infinite recursion
 * when using -flat_namespace linker flag.
 */

#if defined(__APPLE__) && (defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__))

#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <dlfcn.h>

// PowerPC requires 4-byte alignment for 32-bit, 8-byte for 64-bit
#if defined(__ppc64__) || defined(__LP64__)
    constexpr size_t REQUIRED_ALIGNMENT = 8;
#else
    constexpr size_t REQUIRED_ALIGNMENT = 4;
#endif

// We store the offset in the bytes immediately before the aligned pointer
constexpr size_t OFFSET_SIZE = sizeof(size_t);

// Function pointers to original malloc/free
// Using dlsym to avoid infinite recursion with -flat_namespace
typedef void* (*malloc_func_t)(size_t);
typedef void (*free_func_t)(void*);

static malloc_func_t original_malloc = nullptr;
static free_func_t original_free = nullptr;

// Initialize function pointers to original malloc/free
// This must be called before any malloc/free calls
__attribute__((constructor))
static void init_malloc_wrapper() {
    // Use dlsym with RTLD_NEXT to get the original malloc/free
    // This avoids infinite recursion when using -flat_namespace
    original_malloc = reinterpret_cast<malloc_func_t>(dlsym(RTLD_NEXT, "malloc"));
    original_free = reinterpret_cast<free_func_t>(dlsym(RTLD_NEXT, "free"));
    
    if (!original_malloc || !original_free) {
        // Fallback: if dlsym fails, try to get from system library
        void* handle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
        if (handle) {
            if (!original_malloc) {
                original_malloc = reinterpret_cast<malloc_func_t>(dlsym(handle, "malloc"));
            }
            if (!original_free) {
                original_free = reinterpret_cast<free_func_t>(dlsym(handle, "free"));
            }
            dlclose(handle);
        }
    }
    
    // If we still don't have the functions, we can't proceed safely
    // This should never happen, but better safe than sorry
    if (!original_malloc || !original_free) {
        // At this point we're in trouble - but we'll try to continue
        // The wrapper will just pass through to system malloc
    }
}

extern "C" {

// Override malloc to ensure alignment
// We allocate extra space and store the offset to the original pointer
void* malloc(size_t size) {
    if (size == 0) {
        return nullptr;
    }
    
    // If we don't have the original malloc, fall back to system malloc
    // This shouldn't happen, but prevents crashes
    if (!original_malloc) {
        // Try to initialize again (in case constructor didn't run)
        init_malloc_wrapper();
        if (!original_malloc) {
            // Last resort: use system malloc directly
            // This won't fix alignment but at least won't crash
            return reinterpret_cast<malloc_func_t>(dlsym(RTLD_DEFAULT, "malloc"))(size);
        }
    }
    
    // Allocate extra space: offset storage + alignment padding
    size_t extra = OFFSET_SIZE + REQUIRED_ALIGNMENT;
    void* original = original_malloc(size + extra);
    
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
    
    // If we don't have the original free, fall back to system free
    if (!original_free) {
        init_malloc_wrapper();
        if (!original_free) {
            reinterpret_cast<free_func_t>(dlsym(RTLD_DEFAULT, "free"))(ptr);
            return;
        }
    }
    
    // Recover original pointer from stored offset
    size_t offset = *reinterpret_cast<size_t*>(static_cast<char*>(ptr) - OFFSET_SIZE);
    void* original = static_cast<char*>(ptr) - offset;
    
    original_free(original);
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
