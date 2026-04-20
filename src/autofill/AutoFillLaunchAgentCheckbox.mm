#include "AutoFillLaunchAgentCheckbox.h"

#include <Foundation/NSObjCRuntime.h>
#include <QApplication>

#include <AuthenticationServices/AuthenticationServices.h>

#include <ServiceManagement/ServiceManagement.h>

AutoFillLaunchAgentCheckbox::AutoFillLaunchAgentCheckbox(QWidget *parent) : QCheckBox(parent), m_lastCredentialRequestTime(QDateTime::fromMSecsSinceEpoch(0))
{
    connect(qApp, &QApplication::applicationStateChanged, this, &AutoFillLaunchAgentCheckbox::checkCredentialProviderEnabled);
}

void AutoFillLaunchAgentCheckbox::mousePressEvent(QMouseEvent *e) {
    if (e->button() != Qt::LeftButton) {
        return;
    }
    SMAppService *agentService = [SMAppService
        agentServiceWithPlistName:[NSString stringWithFormat:@"%@.plist", @RENDEZVOUS_APP_IDENTIFIER]];
    if (!isChecked()) {
        NSError *error;
        BOOL isRegistered = [agentService registerAndReturnError:&error];
        if (!isRegistered) {
            [SMAppService openSystemSettingsLoginItems];
            return;
        }
    } else {
        BOOL isUnregistered = [agentService unregisterAndReturnError:nil];
        if (!isUnregistered) {
            return;
        }
    }
    QCheckBox::mousePressEvent(e);
}

void AutoFillLaunchAgentCheckbox::checkCredentialProviderEnabled(Qt::ApplicationState state)
{
    if (state != Qt::ApplicationActive) {
        return;
    }

    SMAppService *agentService = [SMAppService
        agentServiceWithPlistName:[NSString stringWithFormat:@"%@.plist", @RENDEZVOUS_APP_IDENTIFIER]];

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
