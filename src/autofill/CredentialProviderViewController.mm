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
    ASPasswordCredential *passwordCredential =
        autoFillService()->getPasswordCredentialFromIdentity(nil);
    [self.extensionContext
        completeRequestWithSelectedCredential:passwordCredential
                            completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypeOneTimeCode: {
    ASOneTimeCodeCredential *oneTimeCodeCredential =
        autoFillService()->getOneTimeCodeCredentialFromIdentity(nil);
    [self.extensionContext
        completeOneTimeCodeRequestWithSelectedCredential:oneTimeCodeCredential
                                       completionHandler:nil];
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
