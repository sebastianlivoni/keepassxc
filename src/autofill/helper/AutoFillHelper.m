#include "AutoFillHelper.h"

#include <os/log.h>

@implementation AutoFillHelper

- (instancetype)init {
  if (self = [super init]) {
    NSString *queueName = [NSString stringWithFormat:@"%s.Queue", HELPER_APP_IDENTIFIER];
    _dispatchQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
  newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AutoFillHelperProtocol)];
  newConnection.exportedObject = self;
  [newConnection resume];
  return YES;
}

- (void)registerEndpoint:(NSXPCListenerEndpoint *)endpoint withReply:(void (^)(NSError *))reply {
    dispatch_async(self.dispatchQueue, ^{
        self.providerEndpoint = endpoint;
        for (void (^pending)(NSXPCListenerEndpoint *, NSError *) in self.pendingReplies) {
            pending(endpoint, nil);
        }
        [self.pendingReplies removeAllObjects];
        if (reply) reply(nil);
    });
}

- (void)getEndpoint:(void (^)(NSXPCListenerEndpoint *, NSError *))reply {
    dispatch_async(self.dispatchQueue, ^{
        if (self.providerEndpoint) {
            reply(self.providerEndpoint, nil);
            return;
        }

        // Freshly (re)started: KeePassXC registers again after our startup
        // notification, so wait briefly instead of failing right away
        if (!self.pendingReplies) {
            self.pendingReplies = [NSMutableArray array];
        }
        void (^pending)(NSXPCListenerEndpoint *, NSError *) = [reply copy];
        [self.pendingReplies addObject:pending];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), self.dispatchQueue, ^{
            if ([self.pendingReplies containsObject:pending]) {
                [self.pendingReplies removeObject:pending];
                pending(nil, [NSError errorWithDomain:@"AutoFillHelper" code:1 userInfo:nil]);
            }
        });
    });
}

@end
