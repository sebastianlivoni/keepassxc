#include <Foundation/Foundation.h>
#include <os/log.h>

#include "AutoFillXPCRendezvous.h"
#include "../AutoFillCodeSigning.h"

int main(void) {
  @autoreleasepool {
    NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@RENDEZVOUS_XPC_SERVICE_NAME];
    AutoFillXPCRendezvous *service = [[AutoFillXPCRendezvous alloc] init];
    listener.delegate = service;
    [listener setConnectionCodeSigningRequirement:CodeSigningRequirementForIdentifiers(@[@APPLE_APP_IDENTIFIER, @AUTOFILL_EXTENSION_IDENTIFIER])];
    [listener resume];
    [[NSRunLoop currentRunLoop] run];
  }
  return 0;
}
