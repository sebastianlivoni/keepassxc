#include "AutoFillXPCService.h"
#include "AutoFillServiceV2.h"
#include "AutoFillXPCRendezvousProtocol.h"
#include <AuthenticationServices/AuthenticationServices.h>
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
      initWithMachServiceName:
          @"6HH7K3R53J.me.livoni.KeePassXC.AutoFillXPCRendezvous"
                      options:0];

  NSXPCInterface *interface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillXPCRendezvousProtocol)];

  self.rendezvousConnection.remoteObjectInterface = interface;
  //[self.rendezvousConnection setCodeSigningRequirement:@"anchor apple generic and identifier \"me.livoni.KeePassXC.AutoFillXPCRendezvous\""];
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
  //[newConnection setCodeSigningRequirement:@"anchor apple generic and identifier \"me.livoni.KeePassXC.AutoFillExtension\""];
  [newConnection resume];
  _connection = newConnection;
  return newConnection;
}

- (void)fetchPasswordCredentialForIdentiity:
            (ASPasswordCredentialIdentity *)identity
                                  withReply:(void (^)(ASPasswordCredential *,
                                                      NSError *))reply {
  autoFillServiceV2()->fetchPasswordCredentialFromIdentity(identity, reply);
}

- (void)fetchOneTimeCodeForIdentity:(ASOneTimeCodeCredentialIdentity *)identity
                          withReply:
                              (void (^)(ASOneTimeCodeCredential *credential,
                                        NSError *error))reply {
  autoFillServiceV2()->fetchOneTimeCodeForIdentity(identity, reply);
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
