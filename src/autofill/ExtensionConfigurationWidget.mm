#include "ExtensionConfigurationWidget.h"

#include <QVBoxLayout>
#include <QMessageBox>
#include <QLabel>

#include "core/Database.h"
#include "core/Group.h"
#include "core/Tools.h"
#include "quickunlock/TouchID.h"

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
    // auto quickLock = new TouchID();

    // //auto key = QSharedPointer<CompositeKey>::create();
    // auto db = QSharedPointer<Database>::create();
    // auto databaseKey = QSharedPointer<CompositeKey>::create();
    // //auto passwordKey = QSharedPointer<PasswordKey>::create("a");
    // //key->addKey(passwordKey);

    // db->setFilePath("/Users/seb/Downloads/Adgangskoder.kdbx");

    // QByteArray keyData;
    // quickLock->getKey(db->publicUuid(), keyData);
    // databaseKey->setRawKey(keyData);

    // QString error;
    // if (db->open(databaseKey, &error)) {
    //     NSLog(@"Hurra låst op");
    // } else {
    //     NSLog(@"Error: %@", error.toNSString());
    //     NSLog(@"Ikke låst op");
    // }
    
    [extensionContext completeExtensionConfigurationRequest];
}