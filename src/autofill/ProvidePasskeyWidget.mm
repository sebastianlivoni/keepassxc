#include "ProvidePasskeyWidget.h"

#include <QLabel>
#include <QMessageBox>
#include <QVBoxLayout>

#include "AutoFillService.h"

#import <LocalAuthentication/LocalAuthentication.h>

ProvidePasskeyWidget::ProvidePasskeyWidget(
    ASCredentialProviderExtensionContext *extensionContext,
    CredentialRequestPtr credentialRequest,
    QWidget *parent)
    : QWidget(parent),
      extensionContext(extensionContext),
      credentialRequest(credentialRequest) {

  // UI setup
  auto *label = new QLabel("Providing Credential", this);
  auto *closeButton = new QPushButton("Close", this);
  connect(closeButton, &QPushButton::clicked, this, &ProvidePasskeyWidget::close);

  auto *layout = new QVBoxLayout(this);
  layout->addWidget(label);
  layout->addWidget(closeButton);
  setLayout(layout);

  resize(500, 300);
  show();

  // Biometrics authentication
  LAContext *context = [[LAContext alloc] init];
  NSError *error = nil;

  if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
    NSString *reason = @"bruge din adgangsnøgle";

    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:reason
                      reply:^(BOOL success, NSError *_Nullable error) {

      if (success) {
        NSLog(@"Authentication successful!");

        auto *request = (ASPasskeyCredentialRequest *)credentialRequest;
        auto *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(request);

        if (!passkeyCredential) {
          NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                               code:ASExtensionErrorCodeFailed
                                           userInfo:nil];
          [extensionContext cancelRequestWithError:error];
          return;
        }

        [extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
      } else {
        NSLog(@"Authentication failed: %@", error.localizedDescription);
        NSError *failError = [NSError errorWithDomain:ASExtensionErrorDomain
                                                 code:ASExtensionErrorCodeFailed
                                             userInfo:nil];
        [extensionContext cancelRequestWithError:failError];
      }
    }];

  } else {
    NSLog(@"Biometric authentication not available: %@", error.localizedDescription);
  }
}

void ProvidePasskeyWidget::close() {
  [extensionContext cancelRequestWithError:
      [NSError errorWithDomain:ASExtensionErrorDomain
                          code:ASExtensionErrorCodeUserCanceled
                      userInfo:nil]];
}
