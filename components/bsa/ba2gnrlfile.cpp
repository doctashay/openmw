#include "ba2gnrlfile.hpp"

#include <algorithm>
#include <cassert>
#include <cstring>
#include <format>
#include <fstream>

#include <zlib.h>

#include <components/esm/fourcc.hpp>
#include <components/files/constrainedfilestream.hpp>
#include <components/files/utils.hpp>
#include <components/misc/endianness.hpp>
#include <components/vfs/pathutil.hpp>

#include "ba2file.hpp"
#include "memorystream.hpp"

namespace
{
    // Helper function for safe aligned reading on PowerPC
    // PowerPC requires aligned memory access, so we read into a char buffer
    // first, then memcpy to the aligned variable
    template<typename T>
    inline void readAligned(std::istream& in, T& value)
    {
        static_assert(std::is_arithmetic_v<T>);
        alignas(T) char buffer[sizeof(T)];
        in.read(buffer, sizeof(T));
        if (in.fail())
            return;
        std::memcpy(&value, buffer, sizeof(T));
    }
}

namespace Bsa
{
    // special marker for invalid records,
    const uint32_t sInvalidOffset = std::numeric_limits<uint32_t>::max();

    BA2GNRLFile::FileRecord::FileRecord()
        : size(0)
        , offset(sInvalidOffset)
    {
    }

    bool BA2GNRLFile::FileRecord::isValid() const
    {
        return offset != sInvalidOffset;
    }

    BA2GNRLFile::BA2GNRLFile() {}

    BA2GNRLFile::~BA2GNRLFile() = default;

    void BA2GNRLFile::loadFiles(uint32_t fileCount, std::istream& in)
    {
        mFiles.clear();
        mFiles.reserve(fileCount);
        for (uint32_t i = 0; i < fileCount; ++i)
        {
            uint32_t nameHash, extHash, dirHash;
            readAligned(in, nameHash);
            readAligned(in, extHash);
            readAligned(in, dirHash);

            FileRecord file;
            uint32_t unknown;
            readAligned(in, unknown);
            readAligned(in, file.offset);
            readAligned(in, file.packedSize);
            readAligned(in, file.size);

            uint32_t baadfood;
            readAligned(in, baadfood);
            // BA2 files are little-endian, convert on big-endian systems
            if constexpr (Misc::IS_BIG_ENDIAN)
            {
                nameHash = Misc::fromLittleEndian(nameHash);
                extHash = Misc::fromLittleEndian(extHash);
                dirHash = Misc::fromLittleEndian(dirHash);
                unknown = Misc::fromLittleEndian(unknown);
                file.offset = Misc::fromLittleEndian(file.offset);
                file.packedSize = Misc::fromLittleEndian(file.packedSize);
                file.size = Misc::fromLittleEndian(file.size);
                baadfood = Misc::fromLittleEndian(baadfood);
            }
            if (baadfood != 0xBAADF00D)
                fail("Corrupted BSA");

            mFolders[dirHash][{ nameHash, extHash }] = file;

            FileStruct fileStruct{};
            fileStruct.mFileSize = file.size;
            fileStruct.mOffset = file.offset;
            mFiles.push_back(fileStruct);
        }
    }

    /// Read header information from the input source
    void BA2GNRLFile::readHeader(std::istream& input)
    {
        assert(!mIsLoaded);

        const std::streamsize fsize = Files::getStreamSizeLeft(input);

        if (fsize < 24) // header is 24 bytes
            fail("File too small to be a valid BSA archive");

        // Get essential header numbers
        uint32_t type, fileCount;
        uint64_t fileTableOffset;
        {
            uint32_t header[4];
            alignas(uint32_t) char headerBuffer[16];
            input.read(headerBuffer, 16);
            std::memcpy(header, headerBuffer, 16);
            readAligned(input, fileTableOffset);

            // BA2 files are little-endian, convert on big-endian systems
            if constexpr (Misc::IS_BIG_ENDIAN)
            {
                header[0] = Misc::fromLittleEndian(header[0]);
                header[1] = Misc::fromLittleEndian(header[1]);
                header[2] = Misc::fromLittleEndian(header[2]);
                header[3] = Misc::fromLittleEndian(header[3]);
                fileTableOffset = Misc::fromLittleEndian(fileTableOffset);
            }

            if (header[0] != ESM::fourCC("BTDX"))
                fail("Unrecognized BA2 signature");
            mVersion = header[1];
            switch (static_cast<BA2Version>(mVersion))
            {
                case BA2Version::Fallout4:
                case BA2Version::Fallout4NextGen_v7:
                case BA2Version::Fallout4NextGen_v8:
                    break;
                case BA2Version::StarfieldGeneral:
                    uint64_t dummy;
                    readAligned(input, dummy);
                    // BA2 files are little-endian, convert on big-endian systems
                    if constexpr (Misc::IS_BIG_ENDIAN)
                        dummy = Misc::fromLittleEndian(dummy);
                    break;
                default:
                    fail("Unrecognized general BA2 version");
            }

            type = header[2];
            fileCount = header[3];
        }

        if (type == ESM::fourCC("GNRL"))
            loadFiles(fileCount, input);
        else
            fail("Unrecognized ba2 version type");

        // Read the string table
        input.seekg(fileTableOffset);
        for (uint32_t i = 0; i < fileCount; ++i)
        {
            std::vector<char> fileName;
            uint16_t fileNameSize;
            readAligned(input, fileNameSize);
            // BA2 files are little-endian, convert on big-endian systems
            if constexpr (Misc::IS_BIG_ENDIAN)
                fileNameSize = Misc::fromLittleEndian(fileNameSize);
            fileName.resize(fileNameSize + 1);
            input.read(fileName.data(), fileNameSize);
            mFileNames.push_back(std::move(fileName));
            mFiles[i].mNameOffset = 0;
            mFiles[i].mNameSize = fileNameSize;
            mFiles[i].mNamesBuffer = &mFileNames.back();
        }
    }

    BA2GNRLFile::FileRecord BA2GNRLFile::getFileRecord(std::string_view str) const
    {
        for (const auto c : str)
        {
            if (((static_cast<unsigned>(c) >> 7U) & 1U) != 0U)
            {
                fail(std::format("File record {} contains unicode characters, refusing to load.", str));
            }
        }

        const VFS::Path::Normalized path(str);

        const std::string_view fileName = path.stem();
        const std::string_view folder = path.parent().value();

        uint32_t folderHash = generateHash(folder);
        auto it = mFolders.find(folderHash);
        if (it == mFolders.end())
            return FileRecord(); // folder not found, return default which has offset of sInvalidOffset

        uint32_t fileHash = generateHash(fileName);
        uint32_t extHash = generateExtensionHash(path.extension().value());
        auto iter = it->second.find({ fileHash, extHash });
        if (iter == it->second.end())
            return FileRecord(); // file not found, return default which has offset of sInvalidOffset
        return iter->second;
    }

    Files::IStreamPtr BA2GNRLFile::getFile(const FileStruct* file)
    {
        FileRecord fileRec = getFileRecord(file->name());
        if (!fileRec.isValid())
        {
            fail("File not found: " + std::string(file->name()));
        }
        return getFile(fileRec);
    }

    void BA2GNRLFile::addFile(const std::string& filename, std::istream& file)
    {
        assert(false); // not implemented yet
        fail("Add file is not implemented for compressed BSA: " + filename);
    }

    Files::IStreamPtr BA2GNRLFile::getFile(const FileRecord& fileRecord)
    {
        const uint32_t inputSize = fileRecord.packedSize ? fileRecord.packedSize : fileRecord.size;
        Files::IStreamPtr streamPtr = Files::openConstrainedFileStream(mFilepath, fileRecord.offset, inputSize);
        auto memoryStreamPtr = std::make_unique<MemoryInputStream>(fileRecord.size);
        if (fileRecord.packedSize)
        {
            std::vector<char> buffer(inputSize);
            streamPtr->read(buffer.data(), inputSize);
            uLongf destSize = static_cast<uLongf>(fileRecord.size);
            int ec = ::uncompress(reinterpret_cast<Bytef*>(memoryStreamPtr->getRawData()), &destSize,
                reinterpret_cast<Bytef*>(buffer.data()), static_cast<uLong>(buffer.size()));

            if (ec != Z_OK)
                fail("zlib uncompress failed: " + std::string(::zError(ec)));
        }
        else
        {
            streamPtr->read(memoryStreamPtr->getRawData(), fileRecord.size);
        }
        return std::make_unique<Files::StreamWithBuffer<MemoryInputStream>>(std::move(memoryStreamPtr));
    }

} // namespace Bsa
