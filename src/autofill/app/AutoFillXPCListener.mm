#include "app/AutoFillXPCListener.h"
#include "app/AutoFillService.h"
#include "helper/AutoFillHelperProtocol.h"
#include <AuthenticationServices/AuthenticationServices.h>
#include <OSLog/OSLog.h>
#include <notify.h>

#include "common/AutoFillCodeSigning.h"

@implementation AutoFillXPCListener

- (instancetype)init {
  self = [super init];
  if (self) {
    _listener = [NSXPCListener anonymousListener];
    _listener.delegate = self;
    _helperNotifyToken = NOTIFY_TOKEN_INVALID;
    [_listener setConnectionCodeSigningRequirement:CodeSigningRequirement(@AUTOFILL_EXTENSION_IDENTIFIER)];
  }
  return self;
}

- (void)start {
  [self.listener resume];

  // The helper only keeps our endpoint in memory; it announces each
  // (re)start, e.g. after its login item is disabled and enabled again
  __weak typeof(self) weakSelf = self;
  int token = NOTIFY_TOKEN_INVALID;
  notify_register_dispatch(HELPER_STARTED_NOTIFICATION, &token, dispatch_get_main_queue(), ^(int) {
    [weakSelf connectToHelper];
  });
  self.helperNotifyToken = token;

  [self connectToHelper];
}

- (void)dealloc {
  if (_helperNotifyToken != NOTIFY_TOKEN_INVALID) {
    notify_cancel(_helperNotifyToken);
  }
}

- (void)connectToHelper {
  [self.helperConnection invalidate];

  NSXPCConnection *connection =
      [[NSXPCConnection alloc] initWithMachServiceName:@HELPER_XPC_SERVICE_NAME options:0];
  connection.remoteObjectInterface = [NSXPCInterface
      interfaceWithProtocol:@protocol(AutoFillHelperProtocol)];
  // Only hand our endpoint to the genuine, correctly signed helper
  [connection setCodeSigningRequirement:CodeSigningRequirement(@HELPER_APP_IDENTIFIER)];
  self.helperConnection = connection;
  [connection resume];

  id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
    os_log_error(OS_LOG_DEFAULT, "XPC error: %{public}@", error);
  }];

  [proxy registerEndpoint:self.listener.endpoint
                withReply:^(NSError *error) {
                  if (error) {
                    os_log_error(OS_LOG_DEFAULT,
                                 "Failed to register provider: %{public}@", error);
                  }
                }];
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
  newConnection.exportedObject = self;
  newConnection.exportedInterface = AutoFillXPCInterface();
  [newConnection resume];
  _connection = newConnection;
  return YES;
}

- (void)fetchPasswordCredentialForIdentity:(ASPasswordCredentialIdentity *)identity interactive:(BOOL)interactive withReply:(void (^)(ASPasswordCredential *, NSError *))reply {
  autoFillService()->fetchPasswordCredentialFromIdentity(identity, interactive, reply);
}

- (void)fetchOneTimeCodeForIdentity:(ASOneTimeCodeCredentialIdentity *)identity interactive:(BOOL)interactive withReply:(void (^)(ASOneTimeCodeCredential *credential, NSError *error))reply {
  autoFillService()->fetchOneTimeCodeForIdentity(identity, interactive, reply);
}

- (void)fetchPasskeyCredentialFromPasskeyRequest: (ASPasskeyCredentialRequest *)request interactive:(BOOL)interactive withReply: (void (^)(ASPasskeyAssertionCredential *, NSError *))reply {
  autoFillService()->fetchPasskeyCredentialFromPasskeyRequest(request, interactive, reply);
}

- (void)fetchExistingPasskeysForRegistrationRequest:(ASPasskeyCredentialRequest *)request
                                        databaseUuid:(NSString *)databaseUuid
                                           withReply:(void (^)(NSArray<NSArray<NSString *> *> *, NSError *))reply {
  autoFillService()->fetchExistingPasskeysForRegistrationRequest(request, databaseUuid, reply);
}

- (void)registerPasskeyForRequest:(ASPasskeyCredentialRequest *)request
                     databaseUuid:(NSString *)databaseUuid
                existingEntryUuid:(NSString *)existingEntryUuid
                        withReply:(void (^)(ASPasskeyRegistrationCredential *, NSError *))reply {
  autoFillService()->registerPasskeyForRequest(request, databaseUuid, existingEntryUuid, reply);
}

- (void)republishCredentialIdentities {
  autoFillService()->republishCredentialStore();
}

@end
