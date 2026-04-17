
#include "AutoFillXCPServiceProtocol.h"
#include <Foundation/Foundation.h>

@interface AutoFillXPCService
    : NSObject <NSXPCListenerDelegate, AutoFillXCPServiceProtocol> {
}

@property(nonatomic, strong) NSXPCConnection *rendezvousConnection;
@property(nonatomic, strong) NSXPCConnection *connection;
@property(nonatomic, strong) NSXPCListener *listener;

- (void)start;

@end
