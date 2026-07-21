#include <AuthenticationServices/AuthenticationServices.h>

#include "ConfirmationWidget.h"

#include <QPushButton>
#include <QWidget>
#include <QSharedPointer>
#include <QLabel>
#include <QLineEdit>

#include "core/Database.h"
#include "core/Entry.h"

class PasswordConfirmationWidget : public ConfirmationWidget
{

public:
    explicit PasswordConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  ASPasswordCredentialRequest* credentialRequest,
                                  QWidget* parent = nullptr);

    void completeRequest() override;
};