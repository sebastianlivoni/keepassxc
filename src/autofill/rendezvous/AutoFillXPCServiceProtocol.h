#ifndef KEEPASSX_AUTOFILL_PROVIDER_PROTOCOL_H
#define KEEPASSX_AUTOFILL_PROVIDER_PROTOCOL_H

#import <Foundation/Foundation.h>

@protocol AutoFillXPCServiceProtocol <NSObject>

- (void)getMessageWithReply:(void (^)(NSString *message, NSError *error))reply;
- (void)fetchPasswordCredentialForRecordIdentifier:(NSString *)recordIdentifier
                                         withReply:
                                             (void (^)(NSString *username,
                                                       NSString *password,
                                                       NSError *error))reply;
- (void)fetchOneTimeCodeForRecordIdentifier:(NSString *)recordIdentifier
                                  withReply:(void (^)(NSString *code,
                                                      NSError *error))reply;

@end

#endif // KEEPASSX_AUTOFILL_PROVIDER_PROTOCOL_H
