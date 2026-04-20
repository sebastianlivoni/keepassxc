#include "AutoFillCredentialProviderCheckbox.h"

#include <QApplication>

#include <AuthenticationServices/AuthenticationServices.h>

AutoFillCredentialProviderCheckbox::AutoFillCredentialProviderCheckbox(QWidget *parent) : QCheckBox(parent), m_lastCredentialRequestTime(QDateTime::fromMSecsSinceEpoch(0))
{
    connect(qApp, &QApplication::applicationStateChanged, this, &AutoFillCredentialProviderCheckbox::checkCredentialProviderEnabled);
}

void AutoFillCredentialProviderCheckbox::mousePressEvent(QMouseEvent *e) {
    if (e->button() != Qt::LeftButton) {
        return;
    }

    const qint64 kCooldownMillis = 10 * 1000;
    qint64 timeSinceLastRequest = m_lastCredentialRequestTime.msecsTo(QDateTime::currentDateTime());

    ASCredentialIdentityStore *store = [ASCredentialIdentityStore sharedStore];
    [store getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState * _Nonnull state) {
        if (timeSinceLastRequest >= kCooldownMillis && !state.isEnabled) {
            m_lastCredentialRequestTime = QDateTime::currentDateTime();

            [ASSettingsHelper requestToTurnOnCredentialProviderExtensionWithCompletionHandler:^(BOOL appWasEnabledForAutoFill) {
                setChecked(appWasEnabledForAutoFill);
            }];
        } else {
            [ASSettingsHelper openCredentialProviderAppSettingsWithCompletionHandler:^(NSError *error) {
                if (error) {
                    NSLog(@"Failed to open Credential Provider settings: %@",
                            error.localizedDescription);
                } else {
                    NSLog(@"Successfully opened Credential Provider settings.");
                }
            }];
        }
    }];
}

void AutoFillCredentialProviderCheckbox::checkCredentialProviderEnabled(Qt::ApplicationState state)
{
    if (state != Qt::ApplicationActive) {
        return;
    }

    ASCredentialIdentityStore *store = [ASCredentialIdentityStore sharedStore];
    [store getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState * _Nonnull state) {
        setChecked(state.enabled);
    }];
}
