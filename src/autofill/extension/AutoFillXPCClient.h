#pragma once

#include "common/AutoFillXPCProtocol.h"
#include <Foundation/Foundation.h>

@interface AutoFillXPCClient: NSObject {
}

@property(nonatomic, strong) NSXPCConnection *helperConnection;
@property(nonatomic, strong) NSXPCConnection *connection;

- (void)start;

@end
