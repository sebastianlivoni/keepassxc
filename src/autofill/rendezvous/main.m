#include <Foundation/Foundation.h>
#include <os/log.h>

#include "AutoFillXPCRendezvous.h"

int main(void) {
  @autoreleasepool {
    NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@RENDEZVOUS_XPC_SERVICE_NAME];
    AutoFillXPCRendezvous *service = [[AutoFillXPCRendezvous alloc] init];
    listener.delegate = service;
    [listener setConnectionCodeSigningRequirement:@"anchor apple generic and (identifier \"" @APPLE_APP_IDENTIFIER "\" or identifier \"" @AUTOFILL_EXTENSION_IDENTIFIER "\")"];
    [listener resume];
    [[NSRunLoop currentRunLoop] run];
  }
  return 0;
}
