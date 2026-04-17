#include "AutofillXPCRendezvous.h"

#include <os/log.h>

@implementation AutofillXPCRendezvous

- (instancetype)init {
  self = [super init];
  if (self) {
    _dispatchQueue =
        dispatch_queue_create("me.livoni.KeePassXC.AutoFillXPCRendezvous.Queue",
                              DISPATCH_QUEUE_SERIAL);
  }
  os_log(OS_LOG_DEFAULT, "Initialized AutofillXPCRendezvous.");
  return self;
}

- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
  newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AutofillXPCRendezvousProtocol)];
  newConnection.exportedObject = self;
  [newConnection resume];
  os_log(OS_LOG_DEFAULT, "New connection");
  return YES;
}

- (void)registerProvider:(NSXPCListenerEndpoint *)endpoint
               withReply:(void (^)(NSError *error))reply {
  void (^replyCopy)(NSError *error) = [reply copy];
  os_log(OS_LOG_DEFAULT, "Registering provider.");
  dispatch_async(self.dispatchQueue, ^{
    self.providerEndpoint = endpoint;
    if (replyCopy) {
      replyCopy(nil);
    }
  });
}

@end
