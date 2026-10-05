#include <AuthenticationServices/AuthenticationServices.h>

#include <QSharedPointer>
#include <QWidget>

#ifndef CONFIRMATIONWIDGET_H
#define CONFIRMATIONWIDGET_H

class ASCredentialRequest;
class Database;
class DatabaseUnlockWidget;

// Unlocks the database of a picked password, one-time code or passkey and completes the request
class ConfirmationWidget : public QWidget
{
public:
    explicit ConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                id<ASCredentialRequest>,
                                QWidget* parent = nullptr);

    // Touch ID without showing this widget; on false, embed it for the unlock UI
    bool tryQuickUnlock();

private:
    void completeRequest();
    void exitCancelRequest();
    // No credential for the request: drop the identity if its entry is gone, then exit
    void exitWithoutCredential();
    void removeStaleIdentityAndExit();

    ASCredentialProviderExtensionContext* m_extensionContext;
    id<ASCredentialRequest> m_credentialRequest;
    QSharedPointer<Database> m_db;
    DatabaseUnlockWidget* m_unlockWidget;
};

#endif
