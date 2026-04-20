#include <Foundation/Foundation.h>
#include <os/log.h>

#include "AutoFillXPCRendezvous.h"

int main(void) {
  @autoreleasepool {
    os_log(OS_LOG_DEFAULT, "KeePassXC AutoFillXPCRendezvous starting.");
    NSXPCListener *listener = [[NSXPCListener alloc]
        initWithMachServiceName:@"6HH7K3R53J.me.livoni.KeePassXC.AutoFillXPCRendezvous"];
    AutoFillXPCRendezvous *service = [[AutoFillXPCRendezvous alloc] init];
    listener.delegate = service;
    [listener setConnectionCodeSigningRequirement:@"anchor apple generic and (identifier \"me.livoni.KeePassXC\" or identifier \"me.livoni.KeePassXC.AutoFillExtension\")"];
    [listener resume];
    [[NSRunLoop currentRunLoop] run];
  }
  return 0;
}
