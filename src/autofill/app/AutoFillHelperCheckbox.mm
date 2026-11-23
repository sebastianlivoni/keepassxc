#include "app/AutoFillHelperCheckbox.h"

#include <Foundation/NSObjCRuntime.h>
#include <QApplication>

#include <AuthenticationServices/AuthenticationServices.h>

#include "common/AutoFillSupport.h"

#include "core/Config.h"

AutoFillHelperCheckbox::AutoFillHelperCheckbox(QWidget* parent)
    : QCheckBox(parent)
{
    connect(qApp, &QApplication::applicationStateChanged, this, &AutoFillHelperCheckbox::checkHelperEnabled);
    checkHelperEnabled(Qt::ApplicationActive);
}

// Called for every user toggle (mouse, keyboard, accessibility); not calling the base vetoes it
void AutoFillHelperCheckbox::nextCheckState()
{
    SMAppService* agentService = autoFillHelperService();
    if (!isChecked()) {
        if (![agentService registerAndReturnError:nil]) {
            [SMAppService openSystemSettingsLoginItems];
            return;
        }
        config()->set(Config::AutoFill_HelperEnabled, true);
        // Stays unchecked until approved; checkHelperEnabled() updates it when the app is active again
        if (agentService.status == SMAppServiceStatusRequiresApproval) {
            [SMAppService openSystemSettingsLoginItems];
            return;
        }
    } else {
        if (![agentService unregisterAndReturnError:nil]) {
            return;
        }
        config()->set(Config::AutoFill_HelperEnabled, false);
    }
    QCheckBox::nextCheckState();
}

void AutoFillHelperCheckbox::checkHelperEnabled(Qt::ApplicationState state)
{
    if (state != Qt::ApplicationActive) {
        return;
    }

    SMAppService* agentService = autoFillHelperService();

    switch (agentService.status) {
    case SMAppServiceStatusEnabled:
        setChecked(true);
        break;
    case SMAppServiceStatusRequiresApproval:
    case SMAppServiceStatusNotFound:
    case SMAppServiceStatusNotRegistered:
        setChecked(false);
        break;
    }
}
