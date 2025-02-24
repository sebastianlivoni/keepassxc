#include "CredentialProviderViewController.h"

#include <QApplication>

#include "AutoFillService.h"
#include "AutoFillViewController.h"
#include "ExtensionConfigurationWidget.h"
#include "CredentialListWidget.h"
#include "PasskeyRegistrationWidget.h"

@implementation CredentialProviderViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  int argc = 0;
  char *argv[] = { nullptr };
  QApplication *qtApp = new QApplication(argc, argv);
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {
  QWidget* widget = new CredentialListWidget(self.extensionContext);

  [self embedQWidget:widget];
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers requestParameters:(ASPasskeyCredentialRequestParameters *) requestParameters { }

- (void)prepareOneTimeCodeCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {}

- (void)prepareInterfaceForPasskeyRegistration:(id<ASCredentialRequest>) registrationRequest {
  ASPasskeyCredentialRequest *passkeyRegistrationRequest = (ASPasskeyCredentialRequest *)registrationRequest;
  ASPasskeyCredentialIdentity *credentialIdentity = (ASPasskeyCredentialIdentity *)passkeyRegistrationRequest.credentialIdentity;

  QWidget* widget = new PasskeyRegistrationWidget(self.extensionContext);

  [self embedQWidget:widget];
}

- (void)prepareInterfaceToProvideCredentialForRequest:(id<ASCredentialRequest>) credentialRequest {}

- (void)provideCredentialWithoutUserInteractionForRequest:(id<ASCredentialRequest>)credentialRequest {
  switch (credentialRequest.type) {
  case ASCredentialRequestTypePassword: {
    ASPasswordCredentialIdentity *credentialIdentity = (ASPasswordCredentialIdentity *)credentialRequest.credentialIdentity;
    ASPasswordCredential *passwordCredential = autoFillService()->getPasswordCredentialFromIdentity(credentialIdentity);
        
    [self.extensionContext completeRequestWithSelectedCredential:passwordCredential completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypeOneTimeCode: {
    ASOneTimeCodeCredentialIdentity *credentialIdentity = (ASOneTimeCodeCredentialIdentity *)credentialRequest.credentialIdentity;
    ASOneTimeCodeCredential *oneTimeCodeCredential = autoFillService()->getOneTimeCodeCredentialFromIdentity(credentialIdentity);
    [self.extensionContext completeOneTimeCodeRequestWithSelectedCredential:oneTimeCodeCredential completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypePasskeyAssertion: {
    ASPasskeyCredentialRequest* request = (ASPasskeyCredentialRequest*)credentialRequest;
    ASPasskeyAssertionCredential *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(request);

    NSLog(@"User Handle (base64): %@", [passkeyCredential.userHandle base64EncodedStringWithOptions:0]);
    NSLog(@"Relying Party: %@", passkeyCredential.relyingParty);
    NSLog(@"Signature (base64): %@", [passkeyCredential.signature base64EncodedStringWithOptions:0]);
    NSLog(@"Client Data Hash (base64): %@", [passkeyCredential.clientDataHash base64EncodedStringWithOptions:0]);
    NSLog(@"Authenticator Data (base64): %@", [passkeyCredential.authenticatorData base64EncodedStringWithOptions:0]);
    NSLog(@"Credential ID (base64): %@", [passkeyCredential.credentialID base64EncodedStringWithOptions:0]);

    [self.extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
    break;
  }
  default:
    NSLog(@"Unhandled credential request type: %@", @(credentialRequest.type));
    break;
  }
}

- (void)performPasskeyRegistrationWithoutUserInteractionIfPossible:(ASPasskeyCredentialRequest *) registrationRequest {}

- (void)embedQWidget:(QWidget *)widget {
  NSView* rootView = (__bridge NSView*)reinterpret_cast<void*>(widget->winId());

  [self.view addSubview:rootView];

  self.view.translatesAutoresizingMaskIntoConstraints = NO;

  [NSLayoutConstraint activateConstraints:@[
    [self.view.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:0],
    [self.view.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:0],
    [self.view.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:0],
    [self.view.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:0]
  ]];

  [self.view.widthAnchor constraintEqualToConstant:rootView.frame.size.width].active = YES;
  [self.view.heightAnchor constraintEqualToConstant:rootView.frame.size.height].active = YES;
}

- (void)prepareInterfaceForExtensionConfiguration {
  QWidget* widget = new ExtensionConfigurationWidget(self.extensionContext);

  [self embedQWidget:widget];
}

- (void)exitWithUserInteractionRequired {
  [self.extensionContext
      cancelRequestWithError:
          [NSError errorWithDomain:ASExtensionErrorDomain
                              code:ASExtensionErrorCodeUserInteractionRequired
                          userInfo:nil]];
}

@end
