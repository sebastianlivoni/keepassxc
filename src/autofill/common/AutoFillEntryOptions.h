#ifndef KEEPASSXC_AUTOFILLENTRYOPTIONS_H
#define KEEPASSXC_AUTOFILLENTRYOPTIONS_H

#include "browser/BrowserService.h"
#include "core/CustomData.h"
#include "core/Entry.h"
#include "core/Global.h"
#include "core/Group.h"

// AutoFill shares the Browser Integration entry options (hide, additional URLs); "ask before
// filling" is its own. All live in the entry's custom data and groups can override them
namespace AutoFillEntryOptions
{
    inline const QString OPTION_ASK_BEFORE_FILLING = QStringLiteral("AutoFillAskBeforeFilling");

    // A group set to Enable or Disable wins over the entry's own value
    inline bool isOptionEnabled(const Entry* entry, const QString& option)
    {
        if (!entry) {
            return false;
        }
        if (const Group* group = entry->group()) {
            switch (group->resolveCustomDataTriState(option)) {
            case Group::Enable:
                return true;
            case Group::Disable:
                return false;
            case Group::Inherit:
                break;
            }
        }
        return entry->customData()->value(option) == TRUE_STR;
    }

    inline bool isHidden(const Entry* entry)
    {
        return isOptionEnabled(entry, BrowserService::OPTION_HIDE_ENTRY);
    }

    inline bool askBeforeFilling(const Entry* entry)
    {
        return isOptionEnabled(entry, OPTION_ASK_BEFORE_FILLING);
    }
} // namespace AutoFillEntryOptions

#endif // KEEPASSXC_AUTOFILLENTRYOPTIONS_H
