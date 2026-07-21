#include "PasskeyRegistrationWidget.h"

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

PasskeyRegistrationWidget::PasskeyRegistrationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    ASPasskeyCredentialRequest *credentialRequest,
    QWidget *parent)
    : ConfirmationWidget(extensionContext, credentialRequest, parent) { }

void PasskeyRegistrationWidget::completeRequest() {
  auto *passkeyRequest = (ASPasskeyCredentialRequest*)m_credentialRequest;
  auto *passkeyCredential = autoFillService()->createPasskeyRegistrationCredential(passkeyRequest, m_db);

  if (!passkeyCredential ) {
    exitCancelRequest();
    return;
  }

  [m_extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
}