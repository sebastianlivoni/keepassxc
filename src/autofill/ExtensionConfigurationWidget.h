#include <AuthenticationServices/AuthenticationServices.h>

#include <QWidget>
#include <QPushButton>

class ExtensionConfigurationWidget : public QWidget
{

public:
    explicit ExtensionConfigurationWidget(ASCredentialProviderExtensionContext* context, QWidget* parent = nullptr);

private slots:
    void close();

private:
    QPushButton *m_button;
    ASCredentialProviderExtensionContext* extensionContext;
};