#include <Foundation/Foundation.h>
#include <notify.h>
#include <os/log.h>

#include "../common/AutoFillCodeSigning.h"
#include "AutoFillHelper.h"

int main(void)
{
    @autoreleasepool {
        NSXPCListener* listener = [[NSXPCListener alloc] initWithMachServiceName:@HELPER_XPC_SERVICE_NAME];
        AutoFillHelper* service = [[AutoFillHelper alloc] init];
        listener.delegate = service;
        [listener setConnectionCodeSigningRequirement:CodeSigningRequirementForIdentifiers(
                                                          @[ @APPLE_APP_IDENTIFIER, @AUTOFILL_EXTENSION_IDENTIFIER ])];
        [listener resume];
        // Tell a running KeePassXC to register its endpoint with this new instance
        notify_post(HELPER_STARTED_NOTIFICATION);
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
