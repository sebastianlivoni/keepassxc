#import <Foundation/Foundation.h>

@protocol AutoFillXPCRendezvousProtocol <NSObject>

- (void)registerEndpoint:(NSXPCListenerEndpoint *)endpoint withReply:(void (^)(NSError *error))reply;
- (void)getEndpoint:(void (^)(NSXPCListenerEndpoint *endpoint, NSError *error))reply;

@end
