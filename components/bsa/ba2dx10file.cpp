#include "ba2dx10file.hpp"

#include <algorithm>
#include <cassert>
#include <cstring>
#include <format>
#include <istream>

#include <zlib.h>

#include <components/esm/fourcc.hpp>
#include <components/files/constrainedfilestream.hpp>
#include <components/files/utils.hpp>
#include <components/misc/endianness.hpp>
#include <components/vfs/pathutil.hpp>

#include "ba2file.hpp"
#include "memorystream.hpp"


namespace Bsa
{
    BA2DX10File::BA2DX10File() {}

    BA2DX10File::~BA2DX10File() = default;

    void BA2DX10File::loadFiles(uint32_t fileCount, std::istream& in)
    {
        mFiles.clear();
        mFiles.reserve(fileCount);
        for (uint32_t i = 0; i < fileCount; ++i)
        {
            uint32_t nameHash, extHash, dirHash;
            readAligned(in, nameHash);
            readAligned(in, extHash);
            readAligned(in, dirHash);
            // BA2 files are little-endian, convert on big-endian systems
            if constexpr (Misc::IS_BIG_ENDIAN)
            {
                nameHash = Misc::fromLittleEndian(nameHash);
                extHash = Misc::fromLittleEndian(extHash);
                dirHash = Misc::fromLittleEndian(dirHash);
            }

            FileRecord file;
            uint8_t unknown;
            readAligned(in, unknown);

            uint8_t nbChunks;
            readAligned(in, nbChunks);

            file.texturesChunks.resize(nbChunks);

            uint16_t chunkHeaderSize;
            readAligned(in, chunkHeaderSize);
            // BA2 files are little-endian, convert on big-endian systems
            if constexpr (Misc::IS_BIG_ENDIAN)
                chunkHeaderSize = Misc::fromLittleEndian(chunkHeaderSize);
            if (chunkHeaderSize != 24)
                fail("Corrupted BSA");

            readAligned(in, file.height);
            readAligned(in, file.width);
            readAligned(in, file.numMips);
            readAligned(in, file.DXGIFormat);
            readAligned(in, file.cubeMaps);
            // BA2 files are little-endian, convert on big-endian systems
            if constexpr (Misc::IS_BIG_ENDIAN)
            {
                file.height = Misc::fromLittleEndian(file.height);
                file.width = Misc::fromLittleEndian(file.width);
                file.cubeMaps = Misc::fromLittleEndian(file.cubeMaps);
            }
            for (auto& texture : file.texturesChunks)
            {
                readAligned(in, texture.offset);
                readAligned(in, texture.packedSize);
                readAligned(in, texture.size);
                readAligned(in, texture.startMip);
                readAligned(in, texture.endMip);
                uint32_t baadfood;
                readAligned(in, baadfood);
                // BA2 files are little-endian, convert on big-endian systems
                if constexpr (Misc::IS_BIG_ENDIAN)
                {
                    texture.offset = Misc::fromLittleEndian(texture.offset);
                    texture.packedSize = Misc::fromLittleEndian(texture.packedSize);
                    texture.size = Misc::fromLittleEndian(texture.size);
                    texture.startMip = Misc::fromLittleEndian(texture.startMip);
                    texture.endMip = Misc::fromLittleEndian(texture.endMip);
                    baadfood = Misc::fromLittleEndian(baadfood);
                }
                if (baadfood != 0xBAADF00D)
                    fail("Corrupted BSA");
            }

            mFolders[dirHash][{ nameHash, extHash }] = std::move(file);

            FileStruct fileStruct{};
            mFiles.push_back(fileStruct);
        }
    }

    /// Read header information from the input source
    void BA2DX10File::readHeader(std::istream& input)
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
                case BA2Version::StarfieldDDS:
                    uint64_t dummy;
                    readAligned(input, dummy);
                    uint32_t compressionMethod;
                    readAligned(input, compressionMethod);
                    // BA2 files are little-endian, convert on big-endian systems
                    if constexpr (Misc::IS_BIG_ENDIAN)
                    {
                        dummy = Misc::fromLittleEndian(dummy);
                        compressionMethod = Misc::fromLittleEndian(compressionMethod);
                    }
                    if (compressionMethod == 3)
                        fail("Unsupported LZ4-compressed DDS BA2");
                    break;
                default:
                    fail("Unrecognized DDS BA2 version");
            }

            type = header[2];
            fileCount = header[3];
        }

        if (type == ESM::fourCC("DX10"))
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
            fileName.resize(fileNameSize + 1, '\0');
            input.read(fileName.data(), fileNameSize);
            std::size_t nameLength = fileNameSize;
            while (nameLength > 0 && fileName[nameLength - 1] == '\0')
                --nameLength;
            mFiles[i].mName.assign(fileName.data(), nameLength);
        }
    }

    std::optional<BA2DX10File::FileRecord> BA2DX10File::getFileRecord(std::string_view str) const
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
            return std::nullopt; // folder not found

        uint32_t fileHash = generateHash(fileName);
        uint32_t extHash = generateExtensionHash(path.extension().value());
        auto iter = it->second.find({ fileHash, extHash });
        if (iter == it->second.end())
            return std::nullopt; // file not found
        return iter->second;
    }

#pragma pack(push)
#pragma pack(1)
    struct DDSHeader
    {
        uint32_t size = 0;
        uint32_t flags = 0;
        uint32_t height = 0;
        uint32_t width = 0;
        uint32_t pitchOrLinearSize = 0;
        uint32_t depth = 0;
        uint32_t mipMapCount = 0;
        uint32_t reserved1[11] = {};
        struct
        {
            uint32_t size = 0;
            uint32_t flags = 0;
            uint32_t fourCC = 0;
            uint32_t RGBBitCount = 0;
            uint32_t RBitMask = 0;
            uint32_t GBitMask = 0;
            uint32_t BBitMask = 0;
            uint32_t ABitMask = 0;
        } ddspf;
        uint32_t caps = 0;
        uint32_t caps2 = 0;
        uint32_t caps3 = 0;
        uint32_t caps4 = 0;
        uint32_t reserved2 = 0;
    };

    struct DDSHeaderDX10 : DDSHeader
    {
        int32_t dxgiFormat = 0;
        uint32_t resourceDimension = 0;
        uint32_t miscFlags = 0;
        uint32_t arraySize = 0;
        uint32_t miscFlags2 = 0;
    };
#pragma pack(pop)

    Files::IStreamPtr BA2DX10File::getFile(const FileStruct* file)
    {
        if (auto fileRec = getFileRecord(file->name()); fileRec)
            return getFile(*fileRec);
        fail("File not found: " + std::string(file->name()));
    }

    void BA2DX10File::addFile(const std::string& filename, std::istream& file)
    {
        assert(false); // not implemented yet
        fail("Add file is not implemented for compressed BSA: " + filename);
    }

    constexpr const uint32_t DDSD_CAPS = 0x00000001;
    constexpr const uint32_t DDSD_HEIGHT = 0x00000002;
    constexpr const uint32_t DDSD_WIDTH = 0x00000004;
    constexpr const uint32_t DDSD_PITCH = 0x00000008;
    constexpr const uint32_t DDSD_PIXELFORMAT = 0x00001000;
    constexpr const uint32_t DDSD_MIPMAPCOUNT = 0x00020000;
    constexpr const uint32_t DDSD_LINEARSIZE = 0x00080000;

    constexpr const uint32_t DDSCAPS_COMPLEX = 0x00000008;
    constexpr const uint32_t DDSCAPS_TEXTURE = 0x00001000;
    constexpr const uint32_t DDSCAPS_MIPMAP = 0x00400000;

    constexpr const uint32_t DDSCAPS2_CUBEMAP = 0x00000200;
    constexpr const uint32_t DDSCAPS2_POSITIVEX = 0x00000400;
    constexpr const uint32_t DDSCAPS2_NEGATIVEX = 0x00000800;
    constexpr const uint32_t DDSCAPS2_POSITIVEY = 0x00001000;
    constexpr const uint32_t DDSCAPS2_NEGATIVEY = 0x00002000;
    constexpr const uint32_t DDSCAPS2_POSITIVEZ = 0x00004000;
    constexpr const uint32_t DDSCAPS2_NEGATIVEZ = 0x00008000;

    constexpr const uint32_t DDPF_ALPHAPIXELS = 0x00000001;
    constexpr const uint32_t DDPF_ALPHA = 0x00000002;
    constexpr const uint32_t DDPF_FOURCC = 0x00000004;
    constexpr const uint32_t DDPF_RGB = 0x00000040;
    constexpr const uint32_t DDPF_LUMINANCE = 0x00020000;

    constexpr const uint32_t DDS_DIMENSION_TEXTURE2D = 0x00000003;
    constexpr const uint32_t DDS_RESOURCE_MISC_TEXTURECUBE = 0x00000004;

    enum DXGI : uint8_t
    {
        DXGI_FORMAT_UNKNOWN = 0,
        DXGI_FORMAT_R32G32B32A32_TYPELESS,
        DXGI_FORMAT_R32G32B32A32_FLOAT,
        DXGI_FORMAT_R32G32B32A32_UINT,
        DXGI_FORMAT_R32G32B32A32_SINT,
        DXGI_FORMAT_R32G32B32_TYPELESS,
        DXGI_FORMAT_R32G32B32_FLOAT,
        DXGI_FORMAT_R32G32B32_UINT,
        DXGI_FORMAT_R32G32B32_SINT,
        DXGI_FORMAT_R16G16B16A16_TYPELESS,
        DXGI_FORMAT_R16G16B16A16_FLOAT,
        DXGI_FORMAT_R16G16B16A16_UNORM,
        DXGI_FORMAT_R16G16B16A16_UINT,
        DXGI_FORMAT_R16G16B16A16_SNORM,
        DXGI_FORMAT_R16G16B16A16_SINT,
        DXGI_FORMAT_R32G32_TYPELESS,
        DXGI_FORMAT_R32G32_FLOAT,
        DXGI_FORMAT_R32G32_UINT,
        DXGI_FORMAT_R32G32_SINT,
        DXGI_FORMAT_R32G8X24_TYPELESS,
        DXGI_FORMAT_D32_FLOAT_S8X24_UINT,
        DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS,
        DXGI_FORMAT_X32_TYPELESS_G8X24_UINT,
        DXGI_FORMAT_R10G10B10A2_TYPELESS,
        DXGI_FORMAT_R10G10B10A2_UNORM,
        DXGI_FORMAT_R10G10B10A2_UINT,
        DXGI_FORMAT_R11G11B10_FLOAT,
        DXGI_FORMAT_R8G8B8A8_TYPELESS,
        DXGI_FORMAT_R8G8B8A8_UNORM,
        DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        DXGI_FORMAT_R8G8B8A8_UINT,
        DXGI_FORMAT_R8G8B8A8_SNORM,
        DXGI_FORMAT_R8G8B8A8_SINT,
        DXGI_FORMAT_R16G16_TYPELESS,
        DXGI_FORMAT_R16G16_FLOAT,
        DXGI_FORMAT_R16G16_UNORM,
        DXGI_FORMAT_R16G16_UINT,
        DXGI_FORMAT_R16G16_SNORM,
        DXGI_FORMAT_R16G16_SINT,
        DXGI_FORMAT_R32_TYPELESS,
        DXGI_FORMAT_D32_FLOAT,
        DXGI_FORMAT_R32_FLOAT,
        DXGI_FORMAT_R32_UINT,
        DXGI_FORMAT_R32_SINT,
        DXGI_FORMAT_R24G8_TYPELESS,
        DXGI_FORMAT_D24_UNORM_S8_UINT,
        DXGI_FORMAT_R24_UNORM_X8_TYPELESS,
        DXGI_FORMAT_X24_TYPELESS_G8_UINT,
        DXGI_FORMAT_R8G8_TYPELESS,
        DXGI_FORMAT_R8G8_UNORM,
        DXGI_FORMAT_R8G8_UINT,
        DXGI_FORMAT_R8G8_SNORM,
        DXGI_FORMAT_R8G8_SINT,
        DXGI_FORMAT_R16_TYPELESS,
        DXGI_FORMAT_R16_FLOAT,
        DXGI_FORMAT_D16_UNORM,
        DXGI_FORMAT_R16_UNORM,
        DXGI_FORMAT_R16_UINT,
        DXGI_FORMAT_R16_SNORM,
        DXGI_FORMAT_R16_SINT,
        DXGI_FORMAT_R8_TYPELESS,
        DXGI_FORMAT_R8_UNORM,
        DXGI_FORMAT_R8_UINT,
        DXGI_FORMAT_R8_SNORM,
        DXGI_FORMAT_R8_SINT,
        DXGI_FORMAT_A8_UNORM,
        DXGI_FORMAT_R1_UNORM,
        DXGI_FORMAT_R9G9B9E5_SHAREDEXP,
        DXGI_FORMAT_R8G8_B8G8_UNORM,
        DXGI_FORMAT_G8R8_G8B8_UNORM,
        DXGI_FORMAT_BC1_TYPELESS,
        DXGI_FORMAT_BC1_UNORM,
        DXGI_FORMAT_BC1_UNORM_SRGB,
        DXGI_FORMAT_BC2_TYPELESS,
        DXGI_FORMAT_BC2_UNORM,
        DXGI_FORMAT_BC2_UNORM_SRGB,
        DXGI_FORMAT_BC3_TYPELESS,
        DXGI_FORMAT_BC3_UNORM,
        DXGI_FORMAT_BC3_UNORM_SRGB,
        DXGI_FORMAT_BC4_TYPELESS,
        DXGI_FORMAT_BC4_UNORM,
        DXGI_FORMAT_BC4_SNORM,
        DXGI_FORMAT_BC5_TYPELESS,
        DXGI_FORMAT_BC5_UNORM,
        DXGI_FORMAT_BC5_SNORM,
        DXGI_FORMAT_B5G6R5_UNORM,
        DXGI_FORMAT_B5G5R5A1_UNORM,
        DXGI_FORMAT_B8G8R8A8_UNORM,
        DXGI_FORMAT_B8G8R8X8_UNORM,
        DXGI_FORMAT_R10G10B10_XR_BIAS_A2_UNORM,
        DXGI_FORMAT_B8G8R8A8_TYPELESS,
        DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
        DXGI_FORMAT_B8G8R8X8_TYPELESS,
        DXGI_FORMAT_B8G8R8X8_UNORM_SRGB,
        DXGI_FORMAT_BC6H_TYPELESS,
        DXGI_FORMAT_BC6H_UF16,
        DXGI_FORMAT_BC6H_SF16,
        DXGI_FORMAT_BC7_TYPELESS,
        DXGI_FORMAT_BC7_UNORM,
        DXGI_FORMAT_BC7_UNORM_SRGB,
        DXGI_FORMAT_AYUV,
        DXGI_FORMAT_Y410,
        DXGI_FORMAT_Y416,
        DXGI_FORMAT_NV12,
        DXGI_FORMAT_P010,
        DXGI_FORMAT_P016,
        DXGI_FORMAT_420_OPAQUE,
        DXGI_FORMAT_YUY2,
        DXGI_FORMAT_Y210,
        DXGI_FORMAT_Y216,
        DXGI_FORMAT_NV11,
        DXGI_FORMAT_AI44,
        DXGI_FORMAT_IA44,
        DXGI_FORMAT_P8,
        DXGI_FORMAT_A8P8,
        DXGI_FORMAT_B4G4R4A4_UNORM,
        DXGI_FORMAT_P208,
        DXGI_FORMAT_V208,
        DXGI_FORMAT_V408
    };

    Files::IStreamPtr BA2DX10File::getFile(const FileRecord& fileRecord)
    {
        DDSHeaderDX10 header;
        header.size = sizeof(DDSHeader);
        header.width = fileRecord.width;
        header.height = fileRecord.height;
        header.flags = DDSD_CAPS | DDSD_PIXELFORMAT | DDSD_WIDTH | DDSD_HEIGHT | DDSD_MIPMAPCOUNT;
        header.caps = DDSCAPS_TEXTURE;
        header.mipMapCount = fileRecord.numMips;
        if (header.mipMapCount > 1)
            header.caps = header.caps | DDSCAPS_MIPMAP | DDSCAPS_COMPLEX;
        header.depth = 0;

        header.resourceDimension = DDS_DIMENSION_TEXTURE2D;
        header.arraySize = 1;

        if (fileRecord.cubeMaps == 2049)
        {
            header.caps = header.caps | DDSCAPS_COMPLEX;
            header.caps2 = DDSCAPS2_CUBEMAP | DDSCAPS2_POSITIVEX | DDSCAPS2_NEGATIVEX | DDSCAPS2_POSITIVEY
                | DDSCAPS2_NEGATIVEY | DDSCAPS2_POSITIVEZ | DDSCAPS2_NEGATIVEZ;
            header.miscFlags = DDS_RESOURCE_MISC_TEXTURECUBE;
        }
        header.ddspf.size = sizeof(header.ddspf);
        switch (DXGI(fileRecord.DXGIFormat))
        {
            case DXGI_FORMAT_BC1_UNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DXT1");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height / 2;
                break;
            }
            case DXGI_FORMAT_BC2_UNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DXT3");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height;
                break;
            }
            case DXGI_FORMAT_BC3_UNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DXT5");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height;
                break;
            }
            case DXGI_FORMAT_BC4_SNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("BC4S");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height / 2;
                break;
            }
            case DXGI_FORMAT_BC4_UNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("BC4U");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height / 2;
                break;
            }
            case DXGI_FORMAT_BC5_SNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("BC5S");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height;
                break;
            }
            case DXGI_FORMAT_BC5_UNORM:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("BC5U");
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height;
                break;
            }
            case DXGI_FORMAT_BC1_UNORM_SRGB:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DX10");
                header.dxgiFormat = int32_t(fileRecord.DXGIFormat);
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height / 2;
                break;
            }
            case DXGI_FORMAT_BC2_UNORM_SRGB:
            case DXGI_FORMAT_BC3_UNORM_SRGB:
            case DXGI_FORMAT_BC6H_UF16:
            case DXGI_FORMAT_BC6H_SF16:
            case DXGI_FORMAT_BC7_UNORM:
            case DXGI_FORMAT_BC7_UNORM_SRGB:
            {
                header.flags = header.flags | DDSD_LINEARSIZE;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DX10");
                header.dxgiFormat = int32_t(fileRecord.DXGIFormat);
                header.pitchOrLinearSize = fileRecord.width * fileRecord.height;
                break;
            }
            case DXGI_FORMAT_B8G8R8A8_UNORM_SRGB:
            case DXGI_FORMAT_B8G8R8X8_UNORM_SRGB:
            case DXGI_FORMAT_R8G8B8A8_SINT:
            case DXGI_FORMAT_R8G8B8A8_UINT:
            case DXGI_FORMAT_R8G8B8A8_UNORM_SRGB:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DX10");
                header.dxgiFormat = int32_t(fileRecord.DXGIFormat);
                header.pitchOrLinearSize = fileRecord.width * 4;
                break;
            }
            case DXGI_FORMAT_R8G8_SINT:
            case DXGI_FORMAT_R8G8_UINT:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DX10");
                header.dxgiFormat = int32_t(fileRecord.DXGIFormat);
                header.pitchOrLinearSize = fileRecord.width * 2;
                break;
            }
            case DXGI_FORMAT_R8_SINT:
            case DXGI_FORMAT_R8_SNORM:
            case DXGI_FORMAT_R8_UINT:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_FOURCC;
                header.ddspf.fourCC = ESM::fourCC("DX10");
                header.dxgiFormat = int32_t(fileRecord.DXGIFormat);
                header.pitchOrLinearSize = fileRecord.width;
                break;
            }
            case DXGI_FORMAT_R8G8B8A8_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_RGB | DDPF_ALPHAPIXELS;
                header.ddspf.RGBBitCount = 32;
                header.ddspf.RBitMask = 0x000000FF;
                header.ddspf.GBitMask = 0x0000FF00;
                header.ddspf.BBitMask = 0x00FF0000;
                header.ddspf.ABitMask = 0xFF000000;
                header.pitchOrLinearSize = fileRecord.width * 4;
                break;
            }
            case DXGI_FORMAT_B8G8R8A8_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_RGB | DDPF_ALPHAPIXELS;
                header.ddspf.RGBBitCount = 32;
                header.ddspf.RBitMask = 0x00FF0000;
                header.ddspf.GBitMask = 0x0000FF00;
                header.ddspf.BBitMask = 0x000000FF;
                header.ddspf.ABitMask = 0xFF000000;
                header.pitchOrLinearSize = fileRecord.width * 4;
                break;
            }
            case DXGI_FORMAT_B8G8R8X8_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_RGB;
                header.ddspf.RGBBitCount = 32;
                header.ddspf.RBitMask = 0x00FF0000;
                header.ddspf.GBitMask = 0x0000FF00;
                header.ddspf.BBitMask = 0x000000FF;
                header.pitchOrLinearSize = fileRecord.width * 4;
                break;
            }
            case DXGI_FORMAT_B5G6R5_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_RGB;
                header.ddspf.RGBBitCount = 16;
                header.ddspf.RBitMask = 0x0000F800;
                header.ddspf.GBitMask = 0x000007E0;
                header.ddspf.BBitMask = 0x0000001F;
                header.pitchOrLinearSize = fileRecord.width * 2;
                break;
            }
            case DXGI_FORMAT_B5G5R5A1_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_RGB | DDPF_ALPHAPIXELS;
                header.ddspf.RGBBitCount = 16;
                header.ddspf.RBitMask = 0x00007C00;
                header.ddspf.GBitMask = 0x000003E0;
                header.ddspf.BBitMask = 0x0000001F;
                header.ddspf.ABitMask = 0x00008000;
                header.pitchOrLinearSize = fileRecord.width * 2;
                break;
            }
            case DXGI_FORMAT_R8G8_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_LUMINANCE | DDPF_ALPHAPIXELS;
                header.ddspf.RGBBitCount = 16;
                header.ddspf.RBitMask = 0x000000FF;
                header.ddspf.ABitMask = 0x0000FF00;
                header.pitchOrLinearSize = fileRecord.width * 2;
                break;
            }
            case DXGI_FORMAT_A8_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_ALPHA;
                header.ddspf.RGBBitCount = 8;
                header.ddspf.ABitMask = 0x000000FF;
                header.pitchOrLinearSize = fileRecord.width;
                break;
            }
            case DXGI_FORMAT_R8_UNORM:
            {
                header.flags = header.flags | DDSD_PITCH;
                header.ddspf.flags = DDPF_LUMINANCE;
                header.ddspf.RGBBitCount = 8;
                header.ddspf.RBitMask = 0x000000FF;
                header.pitchOrLinearSize = fileRecord.width;
                break;
            }
            default:
                break;
        }

        size_t headerSize = (header.ddspf.fourCC == ESM::fourCC("DX10") ? sizeof(DDSHeaderDX10) : sizeof(DDSHeader));

        size_t textureSize = sizeof(uint32_t) + headerSize; //"DDS " + header
        uint32_t maxPackedChunkSize = 0;
        for (const auto& textureChunk : fileRecord.texturesChunks)
        {
            textureSize += textureChunk.size;
            maxPackedChunkSize = std::max(textureChunk.packedSize, maxPackedChunkSize);
        }

        auto memoryStreamPtr = std::make_unique<MemoryInputStream>(textureSize);
        char* buff = memoryStreamPtr->getRawData();
        std::vector<char> inputBuffer(maxPackedChunkSize);

        uint32_t dds = ESM::fourCC("DDS ");
        buff = (char*)std::memcpy(buff, &dds, sizeof(uint32_t)) + sizeof(uint32_t);
        std::memcpy(buff, &header, headerSize);

        size_t offset = sizeof(uint32_t) + headerSize;
        // append chunks
        for (const auto& c : fileRecord.texturesChunks)
        {
            const uint32_t inputSize = c.packedSize != 0 ? c.packedSize : c.size;
            Files::IStreamPtr streamPtr = Files::openConstrainedFileStream(mFilepath, c.offset, inputSize);
            if (c.packedSize != 0)
            {
                streamPtr->read(inputBuffer.data(), c.packedSize);
                uLongf destSize = static_cast<uLongf>(c.size);
                int ec = ::uncompress(reinterpret_cast<Bytef*>(memoryStreamPtr->getRawData() + offset), &destSize,
                    reinterpret_cast<Bytef*>(inputBuffer.data()), static_cast<uLong>(c.packedSize));

                if (ec != Z_OK)
                    fail("zlib uncompress failed: " + std::string(::zError(ec)));
            }
            // uncompressed chunk
            else
            {
                streamPtr->read(memoryStreamPtr->getRawData() + offset, c.size);
            }
            offset += c.size;
        }

        return std::make_unique<Files::StreamWithBuffer<MemoryInputStream>>(std::move(memoryStreamPtr));
    }

} // namespace Bsa
