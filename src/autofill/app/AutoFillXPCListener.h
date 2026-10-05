#ifndef KEEPASSXC_AUTOFILLXPCLISTENER_H
#define KEEPASSXC_AUTOFILLXPCLISTENER_H

#include "common/AutoFillXPCProtocol.h"
#include <Foundation/Foundation.h>

@interface AutoFillXPCListener : NSObject <NSXPCListenerDelegate, AutoFillXPCProtocol>

@property(nonatomic, strong) NSXPCConnection *helperConnection;
@property(nonatomic, strong) NSXPCConnection *connection;
@property(nonatomic, strong) NSXPCListener *listener;
@property(nonatomic, assign) int helperNotifyToken;

- (void)start;

@end

#endif // KEEPASSXC_AUTOFILLXPCLISTENER_H
