#include "CredentialListWidget.h"

#include <QVBoxLayout>
#include <QMessageBox>
#include <QLabel>

CredentialListWidget::CredentialListWidget(ASCredentialProviderExtensionContext* context, QWidget* parent) : QWidget(parent), extensionContext(context)
{    
    QLabel* label = new QLabel("KeePassXC AutoFill Credentials", this);

    QPushButton* closeButton = new QPushButton("Close", this);
    connect(closeButton, &QPushButton::clicked, this, &CredentialListWidget::close);

    QVBoxLayout *layout = new QVBoxLayout(this);
    layout->addWidget(label);
    layout->addWidget(closeButton);

    setLayout(layout);

    resize(500, 300);
    show();
}


void CredentialListWidget::close()
{
    [extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                        code:ASExtensionErrorCodeUserCanceled
                                    userInfo:nil]];
}