#include <AuthenticationServices/AuthenticationServices.h>

#include <QWidget>
#include <QPushButton>

class CredentialListWidget : public QWidget
{

public:
    explicit CredentialListWidget(ASCredentialProviderExtensionContext* context, QWidget* parent = nullptr);

private slots:
    void close();

private:
    QPushButton *m_button;
    ASCredentialProviderExtensionContext* extensionContext;
};