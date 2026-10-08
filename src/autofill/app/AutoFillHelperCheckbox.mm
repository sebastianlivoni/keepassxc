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
}

void AutoFillHelperCheckbox::mousePressEvent(QMouseEvent* e)
{
    if (e->button() != Qt::LeftButton) {
        return;
    }
    SMAppService* agentService = autoFillHelperService();
    if (!isChecked()) {
        NSError* error;
        BOOL isRegistered = [agentService registerAndReturnError:&error];
        if (!isRegistered) {
            [SMAppService openSystemSettingsLoginItems];
            return;
        }
        config()->set(Config::AutoFill_HelperEnabled, true);
    } else {
        BOOL isUnregistered = [agentService unregisterAndReturnError:nil];
        if (!isUnregistered) {
            return;
        }
        config()->set(Config::AutoFill_HelperEnabled, false);
    }
    QCheckBox::mousePressEvent(e);
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
