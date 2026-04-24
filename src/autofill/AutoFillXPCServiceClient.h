#pragma once

#include "AutoFillXPCServiceProtocol.h"
#include <Foundation/Foundation.h>

@interface AutoFillXPCServiceClient: NSObject {
}

@property(nonatomic, strong) NSXPCConnection *rendezvousConnection;
@property(nonatomic, strong) NSXPCConnection *connection;

- (void)start;

@end
