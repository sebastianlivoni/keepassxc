
#include <Foundation/Foundation.h>
#include "AutofillXPCRendezvousProtocol.h"

@interface AutofillXPCRendezvous
    : NSObject <NSXPCListenerDelegate, AutofillXPCRendezvousProtocol>

@property(nonatomic, strong) NSXPCListenerEndpoint *providerEndpoint;
@property(nonatomic, strong) dispatch_queue_t dispatchQueue;

@end
