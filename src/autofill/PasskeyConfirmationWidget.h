#include <AuthenticationServices/AuthenticationServices.h>

#include "ConfirmationWidget.h"

#include <QPushButton>
#include <QWidget>
#include <QSharedPointer>
#include <QLabel>
#include <QLineEdit>

#include "core/Database.h"
#include "core/Entry.h"

class PasskeyConfirmationWidget : public ConfirmationWidget
{

public:
    explicit PasskeyConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  ASPasskeyCredentialRequest* credentialRequest,
                                  QWidget* parent = nullptr);

    void completeRequest() override;
};