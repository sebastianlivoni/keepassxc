#include "PasskeyConfirmationWidget.h"

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

PasskeyConfirmationWidget::PasskeyConfirmationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    ASPasskeyCredentialRequest *credentialRequest,
    QWidget *parent)
    : ConfirmationWidget(extensionContext, credentialRequest, parent) { }

void PasskeyConfirmationWidget::completeRequest() {
  auto *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(m_credentialRequest, m_db);
  if (!passkeyCredential) {
    exitCancelRequest();
    return;
  }

  [m_extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
}