#include "AutoFillCredentialProviderCheckbox.h"

#include <QApplication>

#include <AuthenticationServices/AuthenticationServices.h>

#include <ServiceManagement/SMAppService.h>

#include "rendezvous/AutofillXPCRendezvousProtocol.h"

AutoFillCredentialProviderCheckbox::AutoFillCredentialProviderCheckbox(QWidget *parent) : QCheckBox(parent), m_lastCredentialRequestTime(QDateTime::fromMSecsSinceEpoch(0))
{
    /*NSError *error = nil;
    BOOL isEnabled = [[SMAppService mainAppService] registerAndReturnError:&error];

    if (!isEnabled) {
        NSLog(@"Failed to register main app service: %@", error);
    } else {
        NSLog(@"Successfully registered main app service");
    }*/

    NSError *agentError = nil;

    SMAppService *agentService =
        [SMAppService agentServiceWithPlistName:@"me.livoni.KeePassXC.AutoFillService.plist"];

    BOOL agentRegistered = [agentService registerAndReturnError:&agentError];

    if (!agentRegistered) {
        NSLog(@"Failed to register agent service: %@", agentError);
    } else {
        NSLog(@"Successfully registered agent service");
    }

    NSXPCConnection *connection =
        [[NSXPCConnection alloc] initWithMachServiceName:@"me.livoni.KeePassXC.AutoFillXPCRendezvous"
                                                  options:0];

    NSXPCInterface *interface =
        [NSXPCInterface interfaceWithProtocol:@protocol(AutofillXPCRendezvousProtocol)];

    connection.remoteObjectInterface = interface;

    [connection resume];

    id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
        NSLog(@"XPC error: %@", error);
    }];

    NSXPCListener *providerListener = [[NSXPCListener anonymousListener] init];
    NSXPCListenerEndpoint *endpoint = providerListener.endpoint;

    [proxy registerProvider:endpoint withReply:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to register provider: %@", error);
        } else {
            NSLog(@"Provider registered successfully");
        }
    }];

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
