#include "extension/widgets/PasskeyConfirmationWidget.h"

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

PasskeyConfirmationWidget::PasskeyConfirmationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    ASPasskeyCredentialRequest *credentialRequest,
    QWidget *parent)
    : ConfirmationWidget(extensionContext, credentialRequest, parent) { }

void PasskeyConfirmationWidget::completeRequest() {
  auto *passkeyCredential = autoFillCredentials()->getPasskeyCredentialFromPasskeyRequest(static_cast<ASPasskeyCredentialRequest *>(m_credentialRequest), m_db);
  if (!passkeyCredential) {
    exitWithoutCredential();
    return;
  }

  [m_extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
}