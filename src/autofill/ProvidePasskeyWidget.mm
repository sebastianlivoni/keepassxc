#include "ProvidePasskeyWidget.h"

#include <QVBoxLayout>
#include <QMessageBox>
#include <QLabel>

#include "AutoFillService.h"

#import <LocalAuthentication/LocalAuthentication.h>

ProvidePasskeyWidget::ProvidePasskeyWidget(ASCredentialProviderExtensionContext* extensionContext, CredentialRequestPtr credentialRequest, QWidget* parent) : QWidget(parent), extensionContext(extensionContext), credentialRequest(credentialRequest) 
{
    QLabel* label = new QLabel("Providing Credential", this);

    /*QPushButton* registerButton = new QPushButton("Sign in", this);
    connect(registerButton, &QPushButton::clicked, this, &ProvidePasskeyWidget::registerPasskey);*/

    QPushButton* closeButton = new QPushButton("Close", this);
    connect(closeButton, &QPushButton::clicked, this, &ProvidePasskeyWidget::close);

    QVBoxLayout *layout = new QVBoxLayout(this);
    layout->addWidget(label);
    layout->addWidget(closeButton);

    setLayout(layout);

    resize(500, 300);
    show();

    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;

    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
        NSString *reason = @"bruge din adgangsnøgle";
        
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                localizedReason:reason
                          reply:^(BOOL success, NSError * _Nullable error) {
              if (success) {
                  NSLog(@"Authentication successful!");
                  ASPasskeyCredentialRequest* request = (ASPasskeyCredentialRequest*)credentialRequest;
                  ASPasskeyAssertionCredential *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(request);

                  if (passkeyCredential == nil) {
                      NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                                          code:ASExtensionErrorCodeFailed
                                                      userInfo:@{NSLocalizedDescriptionKey : @"Failed to retrieve passkey credential."}];
                      [extensionContext cancelRequestWithError:error];
                      return;
                  }

                  [extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:^(BOOL expired) {
                      NSLog(@"Assertion completed, expired = %@", expired ? @"YES" : @"NO");
                  }];
                
              } else {
                  NSLog(@"Authentication failed: %@", error.localizedDescription);
              }
        }];
    } else {
        NSLog(@"Biometric authentication not available: %@", error.localizedDescription);
    }
}

void ProvidePasskeyWidget::close()
{
    [extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                        code:ASExtensionErrorCodeUserCanceled
                                    userInfo:nil]];
}