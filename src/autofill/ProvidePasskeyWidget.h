#include <AuthenticationServices/AuthenticationServices.h>

#include <QPushButton>
#include <QWidget>

#ifdef __OBJC__
@class ASCredentialProviderExtensionContext;
@protocol ASCredentialRequest;
typedef id<ASCredentialRequest> CredentialRequestPtr;
#else
typedef void* CredentialRequestPtr; // for plain C++ compilers
class ASCredentialProviderExtensionContext;
#endif

class ProvidePasskeyWidget : public QWidget
{

public:
    explicit ProvidePasskeyWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  CredentialRequestPtr credentialRequest,
                                  QWidget* parent = nullptr);

private slots:
    void close();

private:
    QPushButton* m_button;
    ASCredentialProviderExtensionContext* extensionContext;
    CredentialRequestPtr credentialRequest;
};