#include "ProvidePasskeyWidget.h"

#include <QLabel>
#include <QMessageBox>
#include <QVBoxLayout>

#include "AutoFillService.h"

#import <LocalAuthentication/LocalAuthentication.h>

ProvidePasskeyWidget::ProvidePasskeyWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    ASPasskeyCredentialRequest *credentialRequest,
    QWidget *parent)
    : QWidget(parent),
      m_extensionContext(extensionContext),
      m_credentialRequest((ASPasskeyCredentialRequest *)CFBridgingRetain(credentialRequest)) {

  // UI setup
  auto *label = new QLabel("Providing Credential", this);
  /*auto *completeButton = new QPushButton("Complete", this);
  connect(completeButton, &QPushButton::clicked, this, &ProvidePasskeyWidget::complete);*/

  auto *closeButton = new QPushButton("Close", this);
  connect(closeButton, &QPushButton::clicked, this, &ProvidePasskeyWidget::close);

  auto *layout = new QVBoxLayout(this);
  layout->addWidget(label);
  //layout->addWidget(completeButton);
  layout->addWidget(closeButton);
  setLayout(layout);

  resize(500, 300);
  show();

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    complete();
  });
}

void ProvidePasskeyWidget::complete() {
  auto *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(m_credentialRequest);

  if (!passkeyCredential) {
    NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                          code:ASExtensionErrorCodeFailed
                                      userInfo:nil];
    [m_extensionContext cancelRequestWithError:error];
    return;
  }

  [m_extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
}

void ProvidePasskeyWidget::close() {
  [m_extensionContext cancelRequestWithError:
      [NSError errorWithDomain:ASExtensionErrorDomain
                          code:ASExtensionErrorCodeUserCanceled
                      userInfo:nil]];
}

ProvidePasskeyWidget::~ProvidePasskeyWidget() {
    if (m_credentialRequest) {
        CFRelease(m_credentialRequest);
        m_credentialRequest = nullptr;
    }
}