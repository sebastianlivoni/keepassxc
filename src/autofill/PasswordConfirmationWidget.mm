#include "PasswordConfirmationWidget.h"

#include <QLabel>
#include <QMessageBox>
#include <QVBoxLayout>
#include <QPushButton>
#include <QSharedPointer>
#include <QMacNativeWidget>
#include <QWindow>

#include "AutoFillService.h"
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
  auto *passwordRequest = (ASPasswordCredentialRequest*)m_credentialRequest;
  auto *passwordCredential = autoFillService()->getPasswordCredentialFromPasswordRequest(passwordRequest, m_db);
  if (!passwordCredential) {
    exitCancelRequest();
    return;
  }

  [m_extensionContext completeRequestWithSelectedCredential:passwordCredential completionHandler:nil];
}