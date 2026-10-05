#ifndef KEEPASSXC_AUTOFILLDATABASEOPTIONS_H
#define KEEPASSXC_AUTOFILLDATABASEOPTIONS_H

#include "core/CustomData.h"
#include "core/Database.h"
#include "core/Metadata.h"

// Per-database AutoFill options, stored in the database's metadata custom data
namespace AutoFillDatabaseOptions
{
    inline const QString OPTION_DISABLED = QStringLiteral("KPXC_AUTOFILL_DISABLED");

    inline bool isEnabled(const Database* db)
    {
        return db && db->metadata()->customData()->value(OPTION_DISABLED) != QStringLiteral("true");
    }

    inline void setEnabled(Database* db, bool enabled)
    {
        if (!db) {
            return;
        }
        auto* customData = db->metadata()->customData();
        if (enabled) {
            customData->remove(OPTION_DISABLED);
        } else {
            customData->set(OPTION_DISABLED, QStringLiteral("true"));
        }
    }
} // namespace AutoFillDatabaseOptions

#endif // KEEPASSXC_AUTOFILLDATABASEOPTIONS_H
