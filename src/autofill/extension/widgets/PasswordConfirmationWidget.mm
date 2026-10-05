#include "extension/widgets/PasswordConfirmationWidget.h"

#include <QLabel>
#include <QMessageBox>
#include <QVBoxLayout>
#include <QPushButton>
#include <QSharedPointer>
#include <QtWidgets>
#include <QWindow>

#include "common/AutoFillCredentials.h"
#include <LocalAuthentication/LocalAuthentication.h>

#include "core/Tools.h"
#include "quickunlock/QuickUnlockInterface.h"
#include "quickunlock/TouchID.h"

PasswordConfirmationWidget::PasswordConfirmationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    ASPasswordCredentialRequest *credentialRequest,
    QWidget *parent)
    : ConfirmationWidget(extensionContext, credentialRequest, parent) { }

void PasswordConfirmationWidget::completeRequest() {
  auto *passwordRequest = static_cast<ASPasswordCredentialRequest *>(m_credentialRequest);
  auto *passwordCredential = autoFillCredentials()->getPasswordCredentialFromPasswordRequest(passwordRequest, m_db);
  if (!passwordCredential) {
    exitWithoutCredential();
    return;
  }

  [m_extensionContext completeRequestWithSelectedCredential:passwordCredential completionHandler:nil];
}