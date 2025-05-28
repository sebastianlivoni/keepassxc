#include <AuthenticationServices/AuthenticationServices.h>

#include <QPushButton>
#include <QWidget>

class ProvidePasskeyWidget : public QWidget
{

public:
    explicit ProvidePasskeyWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  ASPasskeyCredentialRequest* credentialRequest,
                                  QWidget* parent = nullptr);
    ~ProvidePasskeyWidget();

private slots:
    void complete();
    void close();

private:
    QPushButton* m_button;
    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequest* m_credentialRequest;
};