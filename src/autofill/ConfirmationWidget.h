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

protected:
    explicit ConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                id<ASCredentialRequest>,
                                QWidget* parent = nullptr);
    virtual ~ConfirmationWidget();

    void exitCancelRequest();

    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequest* m_credentialRequest;
    QSharedPointer<Database> m_db;

private:
    DatabaseUnlockWidget* m_unlockWidget;
};

#endif
