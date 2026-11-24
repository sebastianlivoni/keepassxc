#import <Foundation/Foundation.h>

// Darwin notification posted by the helper when it starts, so the
// main app knows to register its endpoint again
#define HELPER_STARTED_NOTIFICATION HELPER_XPC_SERVICE_NAME ".started"

@protocol AutoFillHelperProtocol <NSObject>

- (void)registerEndpoint:(NSXPCListenerEndpoint*)endpoint withReply:(void (^)(NSError* error))reply;
- (void)getEndpoint:(void (^)(NSXPCListenerEndpoint* endpoint, NSError* error))reply;

@end
