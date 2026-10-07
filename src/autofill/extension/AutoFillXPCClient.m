#include "extension/AutoFillXPCClient.h"
#include "common/AutoFillCodeSigning.h"
#include "helper/AutoFillHelperProtocol.h"
#include <Foundation/Foundation.h>
#include <OSLog/OSLog.h>

@implementation AutoFillXPCClient

- (instancetype)init
{
    self = [super init];
    return self;
}

- (void)start
{
    self.helperConnection = [[NSXPCConnection alloc] initWithMachServiceName:@HELPER_XPC_SERVICE_NAME options:0];

    NSXPCInterface* interface = [NSXPCInterface interfaceWithProtocol:@protocol(AutoFillHelperProtocol)];

    self.helperConnection.remoteObjectInterface = interface;
    [self.helperConnection setCodeSigningRequirement:CodeSigningRequirement(@HELPER_APP_IDENTIFIER)];

    [self.helperConnection resume];
}

@end
