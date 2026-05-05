#include "db.hpp"

#include <sqlite3.h>

#include <stdexcept>
#include <string>
#include <string_view>

namespace Sqlite3
{
    void CloseSqlite3::operator()(sqlite3* handle) const noexcept
    {
        // sqlite3_close_v2 was introduced in SQLite 3.7.11
        // For macOS 10.5, always use fallback since v2 might not be in the library
        #if defined(OPENMW_MACOSX_10_5) || (defined(__APPLE__) && defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < 1070)
            // macOS 10.5/10.6: Always use sqlite3_close for compatibility
            sqlite3_close(handle);
        #elif defined(SQLITE_VERSION_NUMBER) && SQLITE_VERSION_NUMBER >= 3007011
            sqlite3_close_v2(handle);
        #else
            sqlite3_close(handle);
        #endif
    }

    Db makeDb(std::string_view path, const char* schema)
    {
        sqlite3* handle = nullptr;
        // All uses of NavMeshDb are protected by a mutex (navmeshtool) or serialized in a single thread (DbWorker)
        // so additional synchronization between threads is not required and SQLITE_OPEN_NOMUTEX can be used.
        // This is unsafe to use NavMeshDb without external synchronization because of internal state.
        const int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX;
        // sqlite3_open_v2 was introduced in SQLite 3.5.0
        // For macOS 10.5, always use fallback since v2 might not be in the library
        #if defined(OPENMW_MACOSX_10_5) || (defined(__APPLE__) && defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED < 1070)
            // macOS 10.5/10.6: Always use sqlite3_open for compatibility
            // Note: We lose the ability to set flags, but sqlite3_open should work
            // The flags (SQLITE_OPEN_NOMUTEX) are just optimizations anyway
            if (const int ec = sqlite3_open(std::string(path).c_str(), &handle); ec != SQLITE_OK)
        #elif defined(SQLITE_VERSION_NUMBER) && SQLITE_VERSION_NUMBER >= 3005000
            if (const int ec = sqlite3_open_v2(std::string(path).c_str(), &handle, flags, nullptr); ec != SQLITE_OK)
        #else
            if (const int ec = sqlite3_open(std::string(path).c_str(), &handle); ec != SQLITE_OK)
        #endif
        {
            const std::string message(sqlite3_errmsg(handle));
            sqlite3_close(handle);
            throw std::runtime_error("Failed to open database: " + message);
        }
        Db result(handle);
        if (const int ec = sqlite3_exec(result.get(), schema, nullptr, nullptr, nullptr); ec != SQLITE_OK)
            throw std::runtime_error("Failed create database schema: " + std::string(sqlite3_errmsg(handle)));
        return result;
    }
}
