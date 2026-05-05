// Fallback implementation for atomic operations when libatomic is not available
// This provides the missing __atomic_fetch_add_8 and __atomic_fetch_sub_8 functions
// using mutex-based synchronization for PowerPC

#if defined(__APPLE__) && (defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__))
    // Only provide fallback on PowerPC macOS when needed
    #include <mutex>
    #include <cstdint>

    namespace
    {
        // Global mutex for atomic operations fallback
        // This is a performance hit but ensures correctness when libatomic is unavailable
        std::mutex g_atomic_fallback_mutex;
    }

    extern "C" {
        // __atomic_fetch_add_8: 64-bit atomic fetch and add
        // GCC expects these to return the old value
        int64_t __atomic_fetch_add_8(volatile void* ptr, int64_t value, int)
        {
            std::lock_guard<std::mutex> lock(g_atomic_fallback_mutex);
            volatile int64_t* int_ptr = reinterpret_cast<volatile int64_t*>(const_cast<void*>(ptr));
            int64_t old_value = *int_ptr;
            *int_ptr = old_value + value;
            return old_value;
        }

        // __atomic_fetch_sub_8: 64-bit atomic fetch and subtract
        int64_t __atomic_fetch_sub_8(volatile void* ptr, int64_t value, int)
        {
            std::lock_guard<std::mutex> lock(g_atomic_fallback_mutex);
            volatile int64_t* int_ptr = reinterpret_cast<volatile int64_t*>(const_cast<void*>(ptr));
            int64_t old_value = *int_ptr;
            *int_ptr = old_value - value;
            return old_value;
        }
    }
#endif
