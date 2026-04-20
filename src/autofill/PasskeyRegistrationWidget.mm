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
    NSView *laView,
    LAContext *laContext,
    QWidget *parent)
    : ConfirmationWidget(extensionContext, credentialRequest, laView, laContext, parent) { }

void PasskeyRegistrationWidget::completeRequest() {
  auto *passkeyCredential = autoFillService()->createPasskeyRegistrationCredential(m_credentialRequest, m_db);

  if (!passkeyCredential ) {
    exitCancelRequest();
    return;
  }

  [m_extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
}