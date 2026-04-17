#include "AutoFillXPCServiceClient.h"
#include "AutofillXPCRendezvousProtocol.h"
#include <Foundation/Foundation.h>
#include <OSLog/OSLog.h>

@implementation AutoFillXPCServiceClient

- (instancetype)init {
  self = [super init];
  return self;
}

- (void)start {
  self.rendezvousConnection = [[NSXPCConnection alloc]
      initWithMachServiceName:@"me.livoni.KeePassXC.AutoFillXPCRendezvous"
                      options:0];

  NSXPCInterface *interface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];

  self.rendezvousConnection.remoteObjectInterface = interface;

  [self.rendezvousConnection resume];

  /*id proxy = [self.rendezvousConnection
      remoteObjectProxyWithErrorHandler:^(NSError *error) {
        os_log_error(OS_LOG_DEFAULT, "XPC error: %{public}@", error);
      }];

  [proxy getEndpointWithReply:^(NSXPCListenerEndpoint *endpoint,
                                NSError *error) {
    if (error) {
      os_log_error(OS_LOG_DEFAULT, "Failed to get endpoint: %{public}@", error);
    } else {
      _connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
      _connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
      _connection.remoteObjectInterface = [NSXPCInterface
          interfaceWithProtocol:@protocol(AutoFillXCPServiceProtocol)];
      [_connection resume];
      os_log(OS_LOG_DEFAULT, "AutoFillXPCServiceClient got client");
    }
  }];*/
}

@end
