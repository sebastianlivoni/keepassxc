#include "CredentialProviderViewController.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <QApplication>
#include <QMacNativeWidget>
#include <QPushButton>
#include <QVBoxLayout>

#include "AutoFillService.h"
#include "BrowserPasskeysConfirmationDialogV2.h"
#include "CredentialListWidget.h"
#include "ExtensionConfigurationWidget.h"
#include "PasskeyConfirmationWidget.h"
#include "PasskeyRegistrationWidget.h"

#include "quickunlock/QuickUnlockInterface.h"
#include "quickunlock/TouchID.h"

#include <LocalAuthentication/LocalAuthentication.h>
#include <LocalAuthenticationEmbeddedUI/LAAuthenticationView.h>
#include <os/log.h>

#include "rendezvous/AutoFillXPCRendezvousProtocol.h"
#include "AutoFillCodeSigning.h"
#include "AutoFillExtensionApplication.h"

@interface CredentialProviderViewController ()

@property(nonatomic, strong) id<ASCredentialRequest> credentialRequest;

@property(nonatomic, strong) LAContext *context;
@property(nonatomic, strong) NSView *rootView;

@end

@implementation CredentialProviderViewController

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil
                         bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    int argc = 0;
    char *argv[] = {nullptr};
    AutoFillExtensionApplication *qtApp = new AutoFillExtensionApplication(argc, argv);

    self.xpcService = [[AutoFillXPCServiceClient alloc] init];
    [self.xpcService start];
    os_log(OS_LOG_DEFAULT, "[AutoFill] Starting XPC rendezvous connection");

    id proxy = [self.xpcService.rendezvousConnection
        remoteObjectProxyWithErrorHandler:^(NSError *error) {
          os_log_error(OS_LOG_DEFAULT,
                       "[AutoFill] Rendezvous connection error: %{public}@",
                       error);
        }];

    [proxy getEndpoint:^(NSXPCListenerEndpoint *endpoint,
                                  NSError *error) {
      if (error) {
        os_log_error(OS_LOG_DEFAULT,
                     "[AutoFill] Failed to obtain service endpoint from "
                     "rendezvous: %{public}@",
                     error);
        return;
      }

      os_log(OS_LOG_DEFAULT, "[AutoFill] Obtained service endpoint, "
                             "establishing direct connection");
      self.xpcService.connection =
          [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
      self.xpcService.connection.remoteObjectInterface = [NSXPCInterface
          interfaceWithProtocol:@protocol(AutoFillXPCServiceProtocol)];
      [self.xpcService.connection setCodeSigningRequirement:CodeSigningRequirement(@APPLE_APP_IDENTIFIER)];
      [self.xpcService.connection resume];

      os_log(OS_LOG_DEFAULT,
             "[AutoFill] Direct connection to AutoFill service established");
    }];

    self.context = [[LAContext alloc] init];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
}

- (void)loadView {
  [super loadView];
}

- (void)viewDidAppear {
  [super viewDidAppear];

  return;

  /*[self.context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
        localizedReason:@"låse din database op"
                  reply:^(BOOL success, NSError * _Nullable error) {
      if (success) {*/
  auto db = [self unlockDatabase];

  if (!db) {
    [self exitCancelRequest];
    return;
  }

  switch (self.credentialRequest.type) {
  case ASCredentialRequestTypePasskeyAssertion: {
    auto *passkeyCredential =
        autoFillService()->getPasskeyCredentialFromPasskeyRequest(
            self.credentialRequest, db);

    if (!passkeyCredential) {
      [self exitCancelRequest];
      return;
    }

    [self.extensionContext
        completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential
                                            completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypePasskeyRegistration: {
    auto *passkeyCredential =
        autoFillService()->createPasskeyRegistrationCredential(
            self.credentialRequest, db);

    if (!passkeyCredential) {
      [self exitCancelRequest];
      return;
    }

    [self.extensionContext
        completeRegistrationRequestWithSelectedPasskeyCredential:
            passkeyCredential
                                               completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypePassword: {
    ASPasswordCredentialIdentity *credentialIdentity = static_cast<ASPasswordCredentialIdentity *>(self.credentialRequest.credentialIdentity);
    auto *passwordCredential = autoFillService()->getPasswordCredentialFromIdentity(credentialIdentity, db);

    if (!passwordCredential) {
      [self exitCancelRequest];
      return;
    }

    [self.extensionContext
        completeRequestWithSelectedCredential:passwordCredential
                            completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypeOneTimeCode: {
    ASOneTimeCodeCredentialIdentity *credentialIdentity =
        static_cast<ASOneTimeCodeCredentialIdentity *>(self.credentialRequest.credentialIdentity);
    ASOneTimeCodeCredential *oneTimeCodeCredential = autoFillService()->getOneTimeCodeCredentialFromIdentity(credentialIdentity, db);

    if (!oneTimeCodeCredential) {
      [self exitCancelRequest];
      return;
    }

    [self.extensionContext
        completeOneTimeCodeRequestWithSelectedCredential:oneTimeCodeCredential
                                       completionHandler:nil];
    break;
  }
  default: {
    /*QWidget* widget = new CredentialListWidget(self.extensionContext);
    [self embedQWidget:widget hideRootView:YES];*/
    break;
  }
  }
  /*} else {
    [self exitCancelRequest];
  }
}];*/
}

- (QSharedPointer<Database>)unlockDatabase {
  auto database = QSharedPointer<Database>::create();
  auto compositeKey = QSharedPointer<CompositeKey>::create();
  const QString dbPath =
      "/Users/seb/Developer/Adgangskoder.kdbx"; // TODO: Get the dbpath somehow

  database->setFilePath(dbPath);

  /*auto quickUnlockInterface =
      qSharedPointerCast<TouchID>(getQuickUnlock()->interface());
  const auto dbUuid = database->publicUuid();

  if (quickUnlockInterface->hasKey(dbUuid)) {
    QByteArray keyData;
    if (!quickUnlockInterface->getKey(dbUuid, keyData)) {
      return nil;
    }
    compositeKey->setRawKey(keyData);
  } else {
    // TODO: Prompt the user for a password securely
    auto passwordKey = QSharedPointer<PasswordKey>::create("a");
    compositeKey->addKey(passwordKey);
  }

  QString error;
  if (!database->open(compositeKey, &error)) {
    NSLog(@"Failed to open database: %@", error.toNSString());
    return nil;
  }*/

  return database;
}

- (void)prepareCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
  QWidget *widget = new CredentialListWidget(self.extensionContext);
  [self embedQWidget:widget hideRootView:NO];

  LAAuthenticationView *laView =
      [[LAAuthenticationView alloc] initWithContext:self.context];
  [self.rootView addSubview:laView];
  self.rootView.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)prepareCredentialListForServiceIdentifiers:
            (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers
                                 requestParameters:
                                     (ASPasskeyCredentialRequestParameters *)
                                         requestParameters {
  // TODO: This will be called for passkeys
}

- (void)prepareOneTimeCodeCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
}

- (void)prepareInterfaceForPasskeyRegistration:
    (id<ASCredentialRequest>)registrationRequest {
        /*id proxy = [self.xpcService.connection remoteObjectProxyWithErrorHandler:^(
                                                   NSError *_Nonnull error) {

        }];

        [proxy createPasskeyRegistrationCredential:registrationRequest withReply:^(ASPasskeyRegistrationCredential *credential, NSError *error) {
            [self.extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
        }];

        return;*/

    ASPasskeyCredentialRequest *passkeyRequest =
            static_cast<ASPasskeyCredentialRequest *>(registrationRequest);

    auto *widget = new BrowserPasskeysConfirmationDialogV2(self.extensionContext, passkeyRequest, self.xpcService);

    ASPasskeyCredentialIdentity *identity = static_cast<ASPasskeyCredentialIdentity*>(passkeyRequest.credentialIdentity);

    QString relyingParty = QString::fromNSString(identity.relyingPartyIdentifier);
    QString username = QString::fromNSString(identity.userName);

    widget->registerCredential(username, relyingParty, {});

    [self embedQWidget:widget hideRootView:NO];

    /*LAAuthenticationView *laView =
      [[LAAuthenticationView alloc] initWithContext:self.context];
  laView.translatesAutoresizingMaskIntoConstraints = NO;

  QWidget *widget = new PasskeyRegistrationWidget(
      self.extensionContext, registrationRequest, laView, self.context);
  [self embedQWidget:widget hideRootView:NO];
  NSView *rootView = (__bridge NSView *)(void *)widget->winId();
  [rootView addSubview:laView];*/

  // self.credentialRequest = registrationRequest;
}

- (void)prepareInterfaceToProvideCredentialForRequest:
    (id<ASCredentialRequest>)credentialRequest {
  LAAuthenticationView *laView =
      [[LAAuthenticationView alloc] initWithContext:self.context];
  laView.translatesAutoresizingMaskIntoConstraints = NO;

  switch (credentialRequest.type) {
  case ASCredentialRequestTypePasskeyAssertion: {
    QWidget *widget = new PasskeyConfirmationWidget(
        self.extensionContext, credentialRequest, laView, self.context);
    [self embedQWidget:widget hideRootView:NO];

    NSView *rootView = (__bridge NSView *)(void *)widget->winId();
    [rootView addSubview:laView];
    break;
  }
  default: {
    break;
  }
  }

  // self.credentialRequest = credentialRequest;
}

- (void)provideCredentialWithoutUserInteractionForRequest:
    (id<ASCredentialRequest>)credentialRequest {
  switch (credentialRequest.type) {
  case ASCredentialRequestTypePassword: {
    ASPasswordCredentialIdentity *identity =
        static_cast<ASPasswordCredentialIdentity *>(
            credentialRequest.credentialIdentity);

    id proxy = [self.xpcService.connection remoteObjectProxyWithErrorHandler:^(
                                               NSError *_Nonnull error) {
      os_log_error(OS_LOG_DEFAULT,
                   "[AutoFill] AutoFill service connection error: %{public}@",
                   error);
    }];

    [proxy
        fetchPasswordCredentialForIdentiity:identity
                                  withReply:^(ASPasswordCredential *credential,
                                              NSError *error) {
                                    [self.extensionContext
                                        completeRequestWithSelectedCredential:
                                            credential
                                                            completionHandler:
                                                                nil];
                                  }];
    break;
  }
  case ASCredentialRequestTypeOneTimeCode: {
    ASOneTimeCodeCredentialIdentity *identity =
        static_cast<ASOneTimeCodeCredentialIdentity *>(
            credentialRequest.credentialIdentity);

    id proxy = [self.xpcService.connection remoteObjectProxyWithErrorHandler:^(
                                               NSError *_Nonnull error) {
      os_log_error(OS_LOG_DEFAULT,
                   "[AutoFill] AutoFill service connection error: %{public}@",
                   error);
    }];

    [proxy
        fetchOneTimeCodeForIdentity:identity
                          withReply:^(ASOneTimeCodeCredential *credential,
                                      NSError *error) {
                            [self.extensionContext
                                completeOneTimeCodeRequestWithSelectedCredential:
                                    credential
                                                               completionHandler:
                                                                   nil];
                          }];
    break;
  }
  case ASCredentialRequestTypePasskeyAssertion: {
    ASPasskeyCredentialRequest *request =
        static_cast<ASPasskeyCredentialRequest *>(credentialRequest);

    id proxy = [self.xpcService.connection remoteObjectProxyWithErrorHandler:^(
                                               NSError *_Nonnull error) {
      os_log_error(OS_LOG_DEFAULT,
                   "[AutoFill] AutoFill service connection error: %{public}@",
                   error);
    }];

    [proxy
        fetchPasskeyCredentialFromPasskeyRequest:request
                                       withReply:^(ASPasskeyAssertionCredential
                                                       *credential,
                                                   NSError *error) {
                                         [self.extensionContext
                                             completeAssertionRequestWithSelectedPasskeyCredential:
                                                 credential
                                                                                 completionHandler:
                                                                                     nil];
                                       }];
    break;
  }
  default: {
    [self exitWithUserInteractionRequired];
    break;
  }
  }
}

- (void)performPasskeyRegistrationWithoutUserInteractionIfPossible:(ASPasskeyCredentialRequest*) registrationRequest {
    NSLog(@"[AutoFill] performPasskeyRegistrationWithoutUserInteractionIfPossible");

    id proxy = [self.xpcService.connection remoteObjectProxyWithErrorHandler:^(
                                               NSError *_Nonnull error) {
      os_log_error(OS_LOG_DEFAULT,
                   "[AutoFill] AutoFill service connection error: %{public}@",
                   error);
    }];

    [proxy createPasskeyRegistrationCredential:registrationRequest withReply:^(ASPasskeyRegistrationCredential *credential, NSError *error) {
        [self.extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
    }];
}

- (void)embedQWidget:(QWidget *)widget hideRootView:(BOOL)hide {
  widget->show();

  NSView *rootView = (__bridge NSView *)(void *)widget->winId();
  if (hide) {
    rootView.frame = NSMakeRect(0, 0, 0, 0);
  }

  [self.view addSubview:rootView];

  self.view.translatesAutoresizingMaskIntoConstraints = NO;

  [NSLayoutConstraint activateConstraints:@[
    [self.view.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:0],
    [self.view.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor
                                            constant:0],
    [self.view.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor
                                             constant:0],
    [self.view.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor
                                           constant:0]
  ]];

  [self.view.widthAnchor constraintEqualToConstant:rootView.frame.size.width]
      .active = YES;
  [self.view.heightAnchor constraintEqualToConstant:rootView.frame.size.height]
      .active = YES;

  self.rootView = rootView;
}

- (void)prepareInterfaceForExtensionConfiguration {
  /*QWidget* widget = new ExtensionConfigurationWidget(self.extensionContext);

  [self embedQWidget:widget hideRootView:NO];*/
}

- (void)exitWithUserInteractionRequired {
  NSError *error =
      [NSError errorWithDomain:ASExtensionErrorDomain
                          code:ASExtensionErrorCodeUserInteractionRequired
                      userInfo:nil];
  [self.extensionContext cancelRequestWithError:error];
}

- (void)exitCancelRequest {
  NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                       code:ASExtensionErrorCodeFailed
                                   userInfo:nil];
  [self.extensionContext cancelRequestWithError:error];
}

@end
