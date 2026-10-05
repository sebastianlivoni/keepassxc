#include <AuthenticationServices/AuthenticationServices.h>

#include <QSharedPointer>
#include <QWidget>

#ifndef CONFIRMATIONWIDGET_H
#define CONFIRMATIONWIDGET_H

class ASCredentialRequest;
class Database;
class DatabaseUnlockWidget;

class ConfirmationWidget : public QWidget
{
public:
    virtual void completeRequest() = 0;
    // Touch ID without showing this widget; on false, embed it for the unlock UI
    bool tryQuickUnlock();

protected:
    explicit ConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                id<ASCredentialRequest>,
                                QWidget* parent = nullptr);
    virtual ~ConfirmationWidget();

    void exitCancelRequest();
    // No credential for the request: drop the identity if its entry is gone, then exit
    void exitWithoutCredential();
    void removeStaleIdentityAndExit();

    ASCredentialProviderExtensionContext* m_extensionContext;
    id<ASCredentialRequest> m_credentialRequest;
    QSharedPointer<Database> m_db;

private:
    DatabaseUnlockWidget* m_unlockWidget;
};

#endif
