#ifndef KEEPASSXC_AUTOFILLXPCPROTOCOL_H
#define KEEPASSXC_AUTOFILLXPCPROTOCOL_H

#import <AuthenticationServices/AuthenticationServices.h>
#import <Foundation/Foundation.h>

// Error codes KeePassXC replies with over XPC
typedef NS_ENUM(NSInteger, AutoFillErrorCode) {
    AutoFillErrorCancelled = 1,
    AutoFillErrorBadIdentifier = 400,
    AutoFillErrorApprovalRequired = 401,
    AutoFillErrorNotFound = 404,
    AutoFillErrorSuperseded = 409, // replaced by a newer request of the same kind
    AutoFillErrorLocked = 423, // locked and no UI to unlock from
    AutoFillErrorSaveFailed = 500,
};

static NSString* const AutoFillErrorDomain = @"org.keepassxc.autofill";

static inline NSError* AutoFillError(AutoFillErrorCode code)
{
    return [NSError errorWithDomain:AutoFillErrorDomain code:code userInfo:nil];
}

static inline BOOL IsAutoFillError(NSError* error, AutoFillErrorCode code)
{
    return [error.domain isEqualToString:AutoFillErrorDomain] && error.code == code;
}

@protocol AutoFillXPCProtocol <NSObject>

// interactive: the extension shows its UI, so KeePassXC may ask for approval itself;
// otherwise it replies 401 when approval is required
- (void)fetchPasswordCredentialForIdentity:(ASPasswordCredentialIdentity*)identity
                               interactive:(BOOL)interactive
                                 withReply:(void (^)(ASPasswordCredential* credential, NSError* error))reply;

- (void)fetchOneTimeCodeForIdentity:(ASOneTimeCodeCredentialIdentity*)identity
                        interactive:(BOOL)interactive
                          withReply:(void (^)(ASOneTimeCodeCredential* credential, NSError* error))reply;

- (void)fetchPasskeyCredentialFromPasskeyRequest:(ASPasskeyCredentialRequest*)request
                                     interactive:(BOOL)interactive
                                       withReply:
                                           (void (^)(ASPasskeyAssertionCredential* credential, NSError* error))reply;

// Registration in a database already unlocked in KeePassXC (404 if it isn't).
// Existing passkeys for the relying party are replied as [entryUuidHex, title, username].
- (void)fetchExistingPasskeysForRegistrationRequest:(ASPasskeyCredentialRequest*)request
                                       databaseUuid:(NSString*)databaseUuid
                                          withReply:
                                              (void (^)(NSArray<NSArray<NSString*>*>* entries, NSError* error))reply;

// An empty existingEntryUuid creates a new entry
- (void)registerPasskeyForRequest:(ASPasskeyCredentialRequest*)request
                     databaseUuid:(NSString*)databaseUuid
                existingEntryUuid:(NSString*)existingEntryUuid
                        withReply:(void (^)(ASPasskeyRegistrationCredential* credential, NSError* error))reply;

@end

static inline NSXPCInterface* AutoFillXPCInterface()
{
    NSXPCInterface* interface = [NSXPCInterface interfaceWithProtocol:@protocol(AutoFillXPCProtocol)];
    [interface setClasses:[NSSet setWithObjects:NSArray.class, NSString.class, nil]
              forSelector:@selector(fetchExistingPasskeysForRegistrationRequest:databaseUuid:withReply:)
            argumentIndex:0
                  ofReply:YES];
    return interface;
}

#endif // KEEPASSXC_AUTOFILLXPCPROTOCOL_H
