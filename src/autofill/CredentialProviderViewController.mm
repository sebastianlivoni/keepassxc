#include "CredentialProviderViewController.h"
#include "AutoFillService.h"
#include <AuthenticationServices/AuthenticationServices.h>

@implementation CredentialProviderViewController

- (void)prepareCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
}

- (void)provideCredentialWithoutUserInteractionForRequest:
    (id<ASCredentialRequest>)credentialRequest {
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

- (void)exitWithUserInteractionRequired {
  [self.extensionContext
      cancelRequestWithError:
          [NSError errorWithDomain:ASExtensionErrorDomain
                              code:ASExtensionErrorCodeUserInteractionRequired
                          userInfo:nil]];
}

@end
