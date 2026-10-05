#include "extension/widgets/OneTimeCodeConfirmationWidget.h"

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

OneTimeCodeConfirmationWidget::OneTimeCodeConfirmationWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    ASOneTimeCodeCredentialRequest *credentialRequest,
    QWidget *parent)
    : ConfirmationWidget(extensionContext, credentialRequest, parent) { }

void OneTimeCodeConfirmationWidget::completeRequest() {
  auto *oneTimeCodeCredential = autoFillCredentials()->getOneTimeCodeCredentialFromIdentity(static_cast<ASOneTimeCodeCredentialIdentity *>(m_credentialRequest.credentialIdentity), m_db);
  if (!oneTimeCodeCredential) {
    exitWithoutCredential();
    return;
  }

  [m_extensionContext completeOneTimeCodeRequestWithSelectedCredential:oneTimeCodeCredential completionHandler:nil];
}