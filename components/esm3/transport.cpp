#include "transport.hpp"

#include <components/debug/debuglog.hpp>
#include <components/misc/endianness.hpp>

#include <components/esm3/esmreader.hpp>
#include <components/esm3/esmwriter.hpp>

namespace ESM
{

    void Transport::add(ESMReader& esm)
    {
        if (esm.retSubName().toInt() == fourCC("DODT"))
        {
            Dest dodt;
            esm.getSubComposite(dodt.mPos);
            if constexpr (Misc::IS_BIG_ENDIAN)
            {
                for (float& v : dodt.mPos.pos)
                    v = Misc::fromLittleEndian(v);
                for (float& v : dodt.mPos.rot)
                    v = Misc::fromLittleEndian(v);
            }
            mList.push_back(std::move(dodt));
        }
        else if (esm.retSubName().toInt() == fourCC("DNAM"))
        {
            std::string name = esm.getHString();
            if (mList.empty())
                Log(Debug::Warning) << "Encountered DNAM record without DODT record, skipped.";
            else
                mList.back().mCellName = std::move(name);
        }
    }

    void Transport::save(ESMWriter& esm) const
    {
        for (const Dest& dest : mList)
        {
            esm.writeNamedComposite("DODT", dest.mPos);
            esm.writeHNOCString("DNAM", dest.mCellName);
        }
    }

}
