#include "CredentialProviderViewController.h"
#include "AutoFillService.h"
#include <AuthenticationServices/AuthenticationServices.h>
#include <QApplication>
#include "AutoFillViewController.h"

@implementation CredentialProviderViewController

- (void) viewDidLoad {
  [super viewDidLoad];

  int argc = 0;
  char *argv[] = { nullptr };
  QApplication *qtApp = new QApplication(argc, argv);

  AutoFillViewController *autoFillViewController = [[AutoFillViewController alloc] init];
  [self addChildViewController:autoFillViewController];
  [self.view addSubview:autoFillViewController.view];

  autoFillViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
  [NSLayoutConstraint activateConstraints:@[
    [autoFillViewController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0],
    [autoFillViewController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:0],
    [autoFillViewController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:0],
    [autoFillViewController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:0],
    [autoFillViewController.view.widthAnchor constraintEqualToConstant:500],
    [autoFillViewController.view.heightAnchor constraintEqualToConstant:300]
  ]];
}

- (void) prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers { }

- (void) prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers requestParameters:(ASPasskeyCredentialRequestParameters *) requestParameters { }

- (void) prepareOneTimeCodeCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {}

- (void) prepareInterfaceForPasskeyRegistration:(id<ASCredentialRequest>) registrationRequest {}

- (void) prepareInterfaceToProvideCredentialForRequest:(id<ASCredentialRequest>) credentialRequest {}

- (void) provideCredentialWithoutUserInteractionForRequest:(id<ASCredentialRequest>)credentialRequest {
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


- (void)prepareInterfaceForExtensionConfiguration {}

- (void)exitWithUserInteractionRequired {
  [self.extensionContext
      cancelRequestWithError:
          [NSError errorWithDomain:ASExtensionErrorDomain
                              code:ASExtensionErrorCodeUserInteractionRequired
                          userInfo:nil]];
}

@end
