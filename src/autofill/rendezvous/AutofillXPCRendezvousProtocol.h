#import <Foundation/Foundation.h>

@protocol AutofillXPCRendezvousProtocol <NSObject>

- (void)registerProvider:(NSXPCListenerEndpoint*)endpoint withReply:(void (^)(NSError* error))reply;

@end
