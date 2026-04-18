#include "AutoFillXPCService.h"
#include "AutoFillServicev2.h"
#include "AutofillXPCRendezvousProtocol.h"
#include <OSLog/OSLog.h>

@implementation AutoFillXPCService

- (instancetype)init {
  self = [super init];
  if (self) {
    _listener = [NSXPCListener anonymousListener];
    _listener.delegate = self;
  }
  return self;
}

- (void)start {
  os_log(OS_LOG_DEFAULT, "Starting AutoFillXPCService");

  self.rendezvousConnection = [[NSXPCConnection alloc]
      initWithMachServiceName:@"6HH7K3R53J.me.livoni.KeePassXC.AutoFillXPCRendezvous"
                      options:0];

  NSXPCInterface *interface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];

  self.rendezvousConnection.remoteObjectInterface = interface;

  [self.rendezvousConnection resume];

  //__weak typeof(self) weakSelf = self;

  id proxy = [self.rendezvousConnection
      remoteObjectProxyWithErrorHandler:^(NSError *error) {
        os_log_error(OS_LOG_DEFAULT, "XPC error: %{public}@", error);
      }];

  NSXPCListenerEndpoint *endpoint = self.listener.endpoint;

  [proxy
      registerProvider:endpoint
             withReply:^(NSError *error) {
               /*__strong typeof(self) strongSelf = weakSelf;
                 if (!strongSelf)
                   return;*/

               if (error) {
                 os_log_error(OS_LOG_DEFAULT,
                              "Failed to register provider: %{public}@", error);
               } else {
                 os_log(OS_LOG_DEFAULT, "Provider registered successfully");
               }
             }];

  [self.listener resume];
}

- (BOOL)listener:(NSXPCListener *)listener
    shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
  newConnection.exportedObject = self;
  newConnection.exportedInterface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCServiceProtocol)];
  os_log(
      OS_LOG_DEFAULT,
      "New connection to AutoFillXPCService from hopefully autofill extension");
  [newConnection resume];
  _connection = newConnection;
  return newConnection;
}

- (void)getMessageWithReply:(void (^__strong)(NSString *__strong,
                                              NSError *__strong))reply {
  autoFillServiceV2()->getMessage(reply);
}

- (void)fetchPasswordCredentialForRecordIdentifier:(NSString *)recordIdentifier
                                         withReply:(void (^)(NSString *,
                                                             NSString *,
                                                             NSError *))reply {
  autoFillServiceV2()->fetchPasswordCredentialForRecordIdentifier(
      recordIdentifier, reply);
}

- (void)fetchOneTimeCodeForRecordIdentifier:(NSString *)recordIdentifier
                                  withReply:(void (^)(NSString *code,
                                                      NSError *error))reply {
  autoFillServiceV2()->fetchOneTimeCodeForRecordIdentifier(recordIdentifier,
                                                           reply);
}

- (void)
    fetchPasskeyCredentialFromPasskeyRequest:
        (ASPasskeyCredentialRequest *)request
                                   withReply:
                                       (void (^)(ASPasskeyAssertionCredential *,
                                                 NSError *))reply {
  autoFillServiceV2()->fetchPasskeyCredentialFromPasskeyRequest(request, reply);
}

@end
