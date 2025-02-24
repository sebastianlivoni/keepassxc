#include "AutoFillCredentialProviderCheckbox.h"

#include <QApplication>

#include <AuthenticationServices/AuthenticationServices.h>

AutoFillCredentialProviderCheckbox::AutoFillCredentialProviderCheckbox(QWidget *parent) : QCheckBox(parent)
{
    connect(qApp, &QApplication::applicationStateChanged, this, &AutoFillCredentialProviderCheckbox::checkCredentialProviderEnabled);
}

void AutoFillCredentialProviderCheckbox::mousePressEvent(QMouseEvent *e) {
    if (e->button() == Qt::LeftButton) {
        // TODO: Replace this with below but apparently this does not work
        /*[ASSettingsHelper
            requestToTurnOnCredentialProviderExtensionWithCompletionHandler:^(
                BOOL appWasEnabledForAutoFill) {
                if (appWasEnabledForAutoFill) {
                    NSLog(@"Credential Provider Extension was successfully enabled.");
                } else {
                    NSLog(@"Failed to enable Credential Provider Extension or user "
                        @"canceled.");
                }
            }];*/

        [ASSettingsHelper openCredentialProviderAppSettingsWithCompletionHandler:^(NSError *error) {
            if (error) {
            NSLog(@"Failed to open Credential Provider settings: %@",
                    error.localizedDescription);
            } else {
            NSLog(@"Successfully opened Credential Provider settings.");
            }
        }];
    }
}

void AutoFillCredentialProviderCheckbox::mouseReleaseEvent(QMouseEvent *e) { }

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