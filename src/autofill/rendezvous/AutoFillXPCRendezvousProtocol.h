#import <Foundation/Foundation.h>

@protocol AutoFillXPCRendezvousProtocol <NSObject>

- (void)register:(NSXPCListenerEndpoint *)endpoint withReply:(void (^)(NSError *error))reply;
- (void)getEndpointWithReply:(void (^)(NSXPCListenerEndpoint *endpoint, NSError *error))reply;

@end
