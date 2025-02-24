#include "PasskeyRegistrationWidget.h"

#include <QVBoxLayout>
#include <QMessageBox>
#include <QLabel>

PasskeyRegistrationWidget::PasskeyRegistrationWidget(ASCredentialProviderExtensionContext* context, QWidget* parent) : QWidget(parent), extensionContext(context)
{
    QLabel* label = new QLabel("Passkey Registration", this);

    QPushButton* registerButton = new QPushButton("Register", this);
    connect(registerButton, &QPushButton::clicked, this, &PasskeyRegistrationWidget::registerPasskey);

    QPushButton* closeButton = new QPushButton("Close", this);
    connect(closeButton, &QPushButton::clicked, this, &PasskeyRegistrationWidget::close);

    QVBoxLayout *layout = new QVBoxLayout(this);
    layout->addWidget(label);
    layout->addWidget(registerButton);
    layout->addWidget(closeButton);

    setLayout(layout);

    resize(500, 300);
    show();
}

void PasskeyRegistrationWidget::registerPasskey()
{
    [extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                        code:ASExtensionErrorCodeUserCanceled
                                    userInfo:nil]];
}

void PasskeyRegistrationWidget::close()
{
    [extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                        code:ASExtensionErrorCodeUserCanceled
                                    userInfo:nil]];
}