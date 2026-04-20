#include "AutoFillXPCServiceClient.h"
#include "rendezvous/AutoFillXPCRendezvousProtocol.h"
#include <Foundation/Foundation.h>
#include <OSLog/OSLog.h>

@implementation AutoFillXPCServiceClient

- (instancetype)init {
  self = [super init];
  return self;
}

- (void)start {
  self.rendezvousConnection = [[NSXPCConnection alloc] initWithMachServiceName:@RENDEZVOUS_XPC_SERVICE_NAME options:0];

  NSXPCInterface *interface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];

  self.rendezvousConnection.remoteObjectInterface = interface;
  [self.rendezvousConnection setCodeSigningRequirement:@"anchor apple generic and identifier \"" @RENDEZVOUS_APP_IDENTIFIER "\""];

  [self.rendezvousConnection resume];
}

@end
