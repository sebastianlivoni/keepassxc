#include "app/AutoFillCredentialProviderCheckbox.h"
#include "app/AutoFillService.h"

#include <QApplication>
#include <QPointer>

#include <AuthenticationServices/AuthenticationServices.h>

AutoFillCredentialProviderCheckbox::AutoFillCredentialProviderCheckbox(QWidget *parent) : QCheckBox(parent), m_lastCredentialRequestTime(QDateTime::fromMSecsSinceEpoch(0))
{
    connect(qApp, &QApplication::applicationStateChanged, this, &AutoFillCredentialProviderCheckbox::checkCredentialProviderEnabled);
}

void AutoFillCredentialProviderCheckbox::mousePressEvent(QMouseEvent *e) {
    if (e->button() != Qt::LeftButton) {
        return;
    }

    // AuthenticationServices calls back on a background queue: hop to the main
    // thread and only touch the widget if it still exists
    QPointer<AutoFillCredentialProviderCheckbox> self(this);
    ASCredentialIdentityStore *store = [ASCredentialIdentityStore sharedStore];
    [store getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState * _Nonnull state) {
        const BOOL enabled = state.isEnabled;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self) {
                return;
            }

            const qint64 kCooldownMillis = 10 * 1000;
            qint64 timeSinceLastRequest = self->m_lastCredentialRequestTime.msecsTo(QDateTime::currentDateTime());
            if (timeSinceLastRequest >= kCooldownMillis && !enabled) {
                self->m_lastCredentialRequestTime = QDateTime::currentDateTime();

                [ASSettingsHelper requestToTurnOnCredentialProviderExtensionWithCompletionHandler:^(BOOL appWasEnabledForAutoFill) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self) {
                            self->setChecked(appWasEnabledForAutoFill);
                        }
                        if (appWasEnabledForAutoFill) {
                            autoFillService()->checkCredentialStoreEnabled();
                        }
                    });
                }];
            } else {
                [ASSettingsHelper openCredentialProviderAppSettingsWithCompletionHandler:^(NSError *error) {
                    if (error) {
                        NSLog(@"Failed to open Credential Provider settings: %@", error.localizedDescription);
                    }
                }];
            }
        });
    }];
}

void AutoFillCredentialProviderCheckbox::checkCredentialProviderEnabled(Qt::ApplicationState state)
{
    if (state != Qt::ApplicationActive) {
        return;
    }

    QPointer<AutoFillCredentialProviderCheckbox> self(this);
    ASCredentialIdentityStore *store = [ASCredentialIdentityStore sharedStore];
    [store getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState * _Nonnull storeState) {
        const BOOL enabled = storeState.enabled;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self) {
                self->setChecked(enabled);
            }
        });
    }];
}
