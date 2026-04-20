#include "AutoFillXPCRendezvous.h"

#include <os/log.h>

@implementation AutoFillXPCRendezvous

- (instancetype)init {
  self = [super init];
  if (self) {
    _dispatchQueue =
        dispatch_queue_create("me.livoni.KeePassXC.AutoFillXPCRendezvous.Queue",
                              DISPATCH_QUEUE_SERIAL);
  }
  os_log(OS_LOG_DEFAULT, "Initialized AutoFillXPCRendezvous.");
  return self;
}

- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
  newConnection.exportedInterface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];
  newConnection.exportedObject = self;
  [newConnection resume];
  os_log(OS_LOG_DEFAULT, "New connection");
  return YES;
}

- (void)register:(NSXPCListenerEndpoint *)endpoint
       withReply:(void (^)(NSError *error))reply {
  void (^replyCopy)(NSError *error) = [reply copy];
  dispatch_async(self.dispatchQueue, ^{
    self.providerEndpoint = endpoint;
    os_log(OS_LOG_DEFAULT, "Provider registered.");
    if (replyCopy) {
      replyCopy(nil);
    }
  });
}

- (void)getEndpointWithReply:(void (^)(NSXPCListenerEndpoint *endpoint,
                                       NSError *error))reply {
  void (^replyCopy)(NSXPCListenerEndpoint *, NSError *) = [reply copy];

  dispatch_async(self.dispatchQueue, ^{
    if (!self.providerEndpoint) {
      os_log_error(OS_LOG_DEFAULT, "No provider endpoint available");

      NSError *error = [NSError errorWithDomain:@"AutoFillXPCRendezvous"
                                           code:1
                                       userInfo:nil];
      replyCopy(nil, error);
      return;
    }

    replyCopy(self.providerEndpoint, nil);
  });
}

@end
