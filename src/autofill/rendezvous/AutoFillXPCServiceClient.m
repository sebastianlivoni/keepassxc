#include "AutoFillXPCServiceClient.h"
#include "AutoFillXPCRendezvousProtocol.h"
#include <Foundation/Foundation.h>
#include <OSLog/OSLog.h>

@implementation AutoFillXPCServiceClient

- (instancetype)init {
  self = [super init];
  return self;
}

- (void)start {
  self.rendezvousConnection = [[NSXPCConnection alloc]
      initWithMachServiceName:@"6HH7K3R53J.me.livoni.KeePassXC.AutoFillXPCRendezvous"
                      options:0];

  NSXPCInterface *interface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];

  self.rendezvousConnection.remoteObjectInterface = interface;
  [self.rendezvousConnection setCodeSigningRequirement:@"anchor apple generic and identifier \"me.livoni.KeePassXC.AutoFillXPCRendezvous\""];
  [self.rendezvousConnection resume];
}

@end
