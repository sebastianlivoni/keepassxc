#include <AuthenticationServices/AuthenticationServices.h>

#include <QWidget>
#include <QPushButton>

class PasskeyRegistrationWidget : public QWidget
{

public:
    explicit PasskeyRegistrationWidget(ASCredentialProviderExtensionContext* context, QWidget* parent = nullptr);

private slots:
    void registerPasskey();
    void close();

private:
    QPushButton *m_button;
    ASCredentialProviderExtensionContext* extensionContext;
};