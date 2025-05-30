#include <AuthenticationServices/AuthenticationServices.h>

#include <QSharedPointer>
#include <QWidget>
#include <QPushButton>
#include <QLineEdit>

#include "core/Database.h"
#include "core/Entry.h"

class ConfirmationWidget : public QWidget {
  public:
    virtual void completeRequest() = 0;

  protected:
    explicit ConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                ASPasskeyCredentialRequest* credentialRequest,
                                NSView* laView,
                                LAContext* laContext,
                                QWidget* parent = nullptr);
    virtual ~ConfirmationWidget();

    void setupQuickUnlock();
    void authenticateWithKey();
    bool unlockDatabase(QSharedPointer<CompositeKey> compositeKey);
    void exitCancelRequest();

    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequest* m_credentialRequest;
    NSView* m_laView;
    LAContext* m_laContext;
    QSharedPointer<Database> m_db;

    QPushButton* m_cancel;
    QPushButton* m_submitButton;
    QLineEdit* m_passwordInput;
    QWidget* m_nativeWidget;
};