#include "AutoFillXPCRendezvous.h"

#include <os/log.h>

@implementation AutoFillXPCRendezvous

- (instancetype)init {
  if (self = [super init]) {
    NSString *queueName = [NSString stringWithFormat:@"%s.Queue", RENDEZVOUS_APP_IDENTIFIER];
    _dispatchQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
  newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];
  newConnection.exportedObject = self;
  [newConnection resume];
  return YES;
}

- (void)registerEndpoint:(NSXPCListenerEndpoint *)endpoint withReply:(void (^)(NSError *))reply {
    dispatch_async(self.dispatchQueue, ^{
        self.providerEndpoint = endpoint;
        if (reply) reply(nil);
    });
}

- (void)getEndpoint:(void (^)(NSXPCListenerEndpoint *, NSError *))reply {
    dispatch_async(self.dispatchQueue, ^{
        if (!self.providerEndpoint) {
            reply(nil, [NSError errorWithDomain:@"AutoFillXPCRendezvous" code:1 userInfo:nil]);
            return;
        }
        reply(self.providerEndpoint, nil);
    });
}

@end
