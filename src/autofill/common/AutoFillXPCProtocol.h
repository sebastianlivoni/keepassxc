#ifndef KEEPASSXC_AUTOFILLXPCPROTOCOL_H
#define KEEPASSXC_AUTOFILLXPCPROTOCOL_H

#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>

@protocol AutoFillXPCProtocol <NSObject>

// interactive: the extension shows its UI, so KeePassXC may ask for approval itself;
// otherwise it replies 401 when approval is required
- (void)fetchPasswordCredentialForIdentity:(ASPasswordCredentialIdentity *)identity
                                interactive:(BOOL)interactive
                                         withReply:
                                             (void (^)(ASPasswordCredential *credential,
                                                       NSError *error))reply;

- (void)fetchOneTimeCodeForIdentity:(ASOneTimeCodeCredentialIdentity *)identity
                        interactive:(BOOL)interactive
                                  withReply:(void (^)(ASOneTimeCodeCredential *credential,
                                                      NSError *error))reply;

- (void)fetchPasskeyCredentialFromPasskeyRequest:(ASPasskeyCredentialRequest *)request interactive:(BOOL)interactive withReply:(void (^)(ASPasskeyAssertionCredential *credential, NSError *error))reply;

// Registration in a database already unlocked in KeePassXC (404 if it isn't).
// Existing passkeys for the relying party are replied as [entryUuidHex, title, username].
- (void)fetchExistingPasskeysForRegistrationRequest:(ASPasskeyCredentialRequest *)request
                                        databaseUuid:(NSString *)databaseUuid
                                           withReply:(void (^)(NSArray<NSArray<NSString *> *> *entries,
                                                               NSError *error))reply;

// An empty existingEntryUuid creates a new entry
- (void)registerPasskeyForRequest:(ASPasskeyCredentialRequest *)request
                     databaseUuid:(NSString *)databaseUuid
                existingEntryUuid:(NSString *)existingEntryUuid
                        withReply:(void (^)(ASPasskeyRegistrationCredential *credential,
                                            NSError *error))reply;

@end

static inline NSXPCInterface *AutoFillXPCInterface() {
  NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(AutoFillXPCProtocol)];
  [interface setClasses:[NSSet setWithObjects:NSArray.class, NSString.class, nil]
            forSelector:@selector(fetchExistingPasskeysForRegistrationRequest:databaseUuid:withReply:)
          argumentIndex:0
                ofReply:YES];
  return interface;
}

#endif // KEEPASSXC_AUTOFILLXPCPROTOCOL_H
