#include <Foundation/Foundation.h>
#include <os/log.h>

#include "AutofillXPCRendezvous.h"

int main(void) {
  @autoreleasepool {
    os_log(OS_LOG_DEFAULT, "KeePassXC AutoFillXPCRendezvous starting.");
    NSXPCListener *listener = [[NSXPCListener alloc]
        initWithMachServiceName:@"6HH7K3R53J.me.livoni.KeePassXC.AutoFillXPCRendezvous"];
    AutofillXPCRendezvous *service = [[AutofillXPCRendezvous alloc] init];
    listener.delegate = service;
    [listener resume];
    [[NSRunLoop currentRunLoop] run];
  }
  return 0;
}
