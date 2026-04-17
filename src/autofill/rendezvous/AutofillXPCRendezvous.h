
#include "AutoFillXPCRendezvousProtocol.h"
#include <Foundation/Foundation.h>

@interface AutofillXPCRendezvous
    : NSObject <NSXPCListenerDelegate, AutoFillXPCRendezvousProtocol> {
  NSXPCConnection *_providerConnection;
}

@property(nonatomic, strong) NSXPCListenerEndpoint *providerEndpoint;
@property(nonatomic, strong) dispatch_queue_t dispatchQueue;

//- (NSXPCConnection *)connection;

@end
