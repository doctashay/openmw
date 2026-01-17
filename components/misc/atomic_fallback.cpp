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
        // Note: GCC's built-in uses unsigned long long (uint64_t), so we match that signature
        unsigned long long __atomic_fetch_add_8(volatile void* ptr, unsigned long long value, int)
        {
            std::lock_guard<std::mutex> lock(g_atomic_fallback_mutex);
            volatile unsigned long long* int_ptr = reinterpret_cast<volatile unsigned long long*>(const_cast<void*>(ptr));
            unsigned long long old_value = *int_ptr;
            *int_ptr = old_value + value;
            return old_value;
        }

        // __atomic_fetch_sub_8: 64-bit atomic fetch and subtract
        unsigned long long __atomic_fetch_sub_8(volatile void* ptr, unsigned long long value, int)
        {
            std::lock_guard<std::mutex> lock(g_atomic_fallback_mutex);
            volatile unsigned long long* int_ptr = reinterpret_cast<volatile unsigned long long*>(const_cast<void*>(ptr));
            unsigned long long old_value = *int_ptr;
            *int_ptr = old_value - value;
            return old_value;
        }
    }
#endif
