//
//  CredentialProviderViewController.m
//  lol
//
//  Created by Sebastian Livoni on 31/01/2025.
//

#import "CredentialProviderViewController.h"

@implementation CredentialProviderViewController

- (void)prepareCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
}

- (void)provideCredentialWithoutUserInteractionForRequest:
    (id<ASCredentialRequest>)credentialRequest {
  ASPasswordCredential *passwordCredential =
      [[ASPasswordCredential alloc] initWithUser:@"username"
                                        password:@"password"];
  [self.extensionContext
      completeRequestWithSelectedCredential:passwordCredential
                          completionHandler:nil];
}

- (void)exitWithUserInteractionRequired {
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                                                      code:ASExtensionErrorCodeUserInteractionRequired
                                                                  userInfo:nil]];
}

@end
