#include <AuthenticationServices/AuthenticationServices.h>

#include "ConfirmationWidget.h"

#include <QPushButton>
#include <QWidget>
#include <QSharedPointer>
#include <QLabel>
#include <QLineEdit>

#include "core/Database.h"
#include "core/Entry.h"

class OneTimeCodeConfirmationWidget : public ConfirmationWidget
{

public:
    explicit OneTimeCodeConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  ASOneTimeCodeCredentialRequest* credentialRequest,
                                  NSView* laView,
                                  LAContext *laContext,
                                  QWidget* parent = nullptr);

    void completeRequest() override;
};