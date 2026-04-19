#ifndef KEEPASSX_AUTOFILL_PROVIDER_PROTOCOL_H
#define KEEPASSX_AUTOFILL_PROVIDER_PROTOCOL_H

#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>

@protocol AutoFillXPCServiceProtocol <NSObject>

- (void)getMessageWithReply:(void (^)(NSString *message, NSError *error))reply;
- (void)fetchPasswordCredentialForIdentiity:(ASPasswordCredentialIdentity *)identity
                                         withReply:
                                             (void (^)(ASPasswordCredential *credential,
                                                       NSError *error))reply;
- (void)fetchOneTimeCodeForIdentity:(ASOneTimeCodeCredentialIdentity *)identity
                                  withReply:(void (^)(ASOneTimeCodeCredential *credential,
                                                      NSError *error))reply;

- (void)fetchPasskeyCredentialFromPasskeyRequest:(ASPasskeyCredentialRequest *)request withReply:(void (^)(ASPasskeyAssertionCredential *credential, NSError *error))reply;

@end

#endif // KEEPASSX_AUTOFILL_PROVIDER_PROTOCOL_H
