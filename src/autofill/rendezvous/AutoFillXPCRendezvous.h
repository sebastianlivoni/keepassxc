
#include "AutoFillXPCRendezvousProtocol.h"
#include <Foundation/Foundation.h>

@interface AutoFillXPCRendezvous : NSObject <NSXPCListenerDelegate, AutoFillXPCRendezvousProtocol>

@property(nonatomic, strong) NSXPCListenerEndpoint *providerEndpoint;
@property(nonatomic, strong) dispatch_queue_t dispatchQueue;

@end
