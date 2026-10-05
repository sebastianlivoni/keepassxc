
#include "AutoFillHelperProtocol.h"
#include <Foundation/Foundation.h>

// Rendezvous point between KeePassXC and the AutoFill extension: KeePassXC registers its
// anonymous XPC endpoint here, and the extension fetches it through the helper's Mach service
@interface AutoFillHelper : NSObject <NSXPCListenerDelegate, AutoFillHelperProtocol>

@property(nonatomic, strong) NSXPCListenerEndpoint *providerEndpoint;
@property(nonatomic, strong) dispatch_queue_t dispatchQueue;
@property(nonatomic, strong) NSMutableArray *pendingReplies;

@end
