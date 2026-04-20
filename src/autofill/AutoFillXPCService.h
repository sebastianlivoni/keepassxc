#ifndef KEEPASSX_AUTOFILL_XPCSERVICE_H
#define KEEPASSX_AUTOFILL_XPCSERVICE_H

#include "AutoFillXPCServiceProtocol.h"
#include <Foundation/Foundation.h>

@interface AutoFillXPCService : NSObject <NSXPCListenerDelegate, AutoFillXPCServiceProtocol>

@property(nonatomic, strong) NSXPCConnection *rendezvousConnection;
@property(nonatomic, strong) NSXPCConnection *connection;
@property(nonatomic, strong) NSXPCListener *listener;

- (void)start;

@end

#endif // KEEPASSX_AUTOFILL_XPCSERVICE_H
