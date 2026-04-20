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
  newConnection.exportedInterface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];
  newConnection.exportedObject = self;
  [newConnection resume];
  os_log(OS_LOG_DEFAULT, "New connection");
  return YES;
}

- (void)registerProvider:(NSXPCListenerEndpoint *)endpoint
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

/*- (NSXPCConnection *)connection {
  if (_providerConnection) {
    return _providerConnection;
  }

  if (!self.providerEndpoint) {
    os_log_error(OS_LOG_DEFAULT, "No provider endpoint yet");
    return nil;
  }

  _providerConnection =
      [[NSXPCConnection alloc] initWithListenerEndpoint:self.providerEndpoint];

  _providerConnection.interruptionHandler = ^{
    os_log_info(OS_LOG_DEFAULT, "Provider connection interrupted");
  };

  //__weak AutofillXPCRendezvous *weakSelf = self;
  _providerConnection.invalidationHandler = ^{
    os_log_info(OS_LOG_DEFAULT,
                "AutoFill service provider connection invalidated");
    // AutofillXPCRendezvous *strongSelf = weakSelf;
    // if (strongSelf) {
    //   dispatch_async(strongSelf.dispatchQueue, ^{
    //     strongSelf->_providerConnection = nil;
    //   });
    //   }
  };

  [_providerConnection resume];

  return _providerConnection;
}*/

- (void)getEndpointWithReply:(void (^)(NSXPCListenerEndpoint *endpoint,
                                       NSError *error))reply {
  void (^replyCopy)(NSXPCListenerEndpoint *, NSError *) = [reply copy];

  dispatch_async(self.dispatchQueue, ^{
    if (!self.providerEndpoint) {
      os_log_error(OS_LOG_DEFAULT, "No provider endpoint available");

      NSError *error = [NSError errorWithDomain:@"AutofillXPCRendezvous"
                                           code:1
                                       userInfo:nil];
      replyCopy(nil, error);
      return;
    }

    replyCopy(self.providerEndpoint, nil);
  });
}

@end
