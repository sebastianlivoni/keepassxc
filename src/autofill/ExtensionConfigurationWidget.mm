#include "ExtensionConfigurationWidget.h"

#include <QVBoxLayout>
#include <QMessageBox>
#include <QLabel>

ExtensionConfigurationWidget::ExtensionConfigurationWidget(ASCredentialProviderExtensionContext* context, QWidget* parent) : QWidget(parent), extensionContext(context)
{
    QLabel* label = new QLabel("Configuration of KeePassXC AutoFill", this);

    QPushButton* closeButton = new QPushButton("Close", this);
    connect(closeButton, &QPushButton::clicked, this, &ExtensionConfigurationWidget::close);

    QVBoxLayout *layout = new QVBoxLayout(this);
    layout->addWidget(label);
    layout->addWidget(closeButton);

    setLayout(layout);

    resize(500, 300);
    show();
}

void ExtensionConfigurationWidget::close()
{
    [extensionContext completeExtensionConfigurationRequest];
}
