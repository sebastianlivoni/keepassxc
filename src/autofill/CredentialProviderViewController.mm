#include "CredentialProviderViewController.h"

#include <QApplication>
#include <QMacNativeWidget>
#include <QVBoxLayout>
#include <QPushButton>

#include "AutoFillService.h"
#include "AutoFillViewController.h"
#include "ExtensionConfigurationWidget.h"
#include "CredentialListWidget.h"
#include "PasskeyConfirmationWidget.h"

#include "quickunlock/QuickUnlockInterface.h"
#include "quickunlock/TouchID.h"

#include <LocalAuthentication/LocalAuthentication.h>
#include <LocalAuthenticationEmbeddedUI/LAAuthenticationView.h>

@interface CredentialProviderViewController()

@property (nonatomic, strong) id<ASCredentialRequest> credentialRequest;

@property (nonatomic, strong) LAContext *context;
@property (nonatomic, strong) NSView *rootView;

@end

@implementation CredentialProviderViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  int argc = 0;
  char *argv[] = { nullptr };
  QApplication *qtApp = new QApplication(argc, argv);

  self.context = [[LAContext alloc] init];
}

- (void)viewDidAppear {
  [super viewDidAppear];

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
              auto *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(self.credentialRequest, db);

              if (!passkeyCredential ) {
                [self exitCancelRequest];
                return;
              }

              [self.extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
              break;
            }
            case ASCredentialRequestTypePasskeyRegistration: {
              auto *passkeyCredential  = autoFillService()->createPasskeyRegistrationCredential(self.credentialRequest, db);

              if (!passkeyCredential ) {
                [self exitCancelRequest];
                return;
              }

              [self.extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
              break;
            }
            case ASCredentialRequestTypePassword: {
              ASPasswordCredentialIdentity *credentialIdentity = (ASPasswordCredentialIdentity *)self.credentialRequest.credentialIdentity;
              auto *passwordCredential = autoFillService()->getPasswordCredentialFromIdentity(credentialIdentity, db);

              if (!passwordCredential ) {
                [self exitCancelRequest];
                return;
              }

              [self.extensionContext completeRequestWithSelectedCredential:passwordCredential completionHandler:nil];
              break;
            }
            case ASCredentialRequestTypeOneTimeCode: {
              ASOneTimeCodeCredentialIdentity *credentialIdentity = (ASOneTimeCodeCredentialIdentity *)self.credentialRequest.credentialIdentity;
              ASOneTimeCodeCredential *oneTimeCodeCredential = autoFillService()->getOneTimeCodeCredentialFromIdentity(credentialIdentity, db);

              if (!oneTimeCodeCredential ) {
                [self exitCancelRequest];
                return;
              }

              [self.extensionContext completeOneTimeCodeRequestWithSelectedCredential:oneTimeCodeCredential completionHandler:nil];
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
  const QString dbPath = "/Users/seb/Downloads/Adgangskoder.kdbx"; // TODO: Get the dbpath somehow

  database->setFilePath(dbPath);

  auto quickUnlockInterface = qSharedPointerCast<TouchID>(getQuickUnlock()->interface());
  const auto dbUuid = database->publicUuid();

  if (quickUnlockInterface->hasKey(dbUuid)) {
    QByteArray keyData;
    if (!quickUnlockInterface->getKey(dbUuid, keyData/*, self.context*/)) {
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
  }

  return database;
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {
  QWidget* widget = new CredentialListWidget(self.extensionContext);
  [self embedQWidget:widget hideRootView:NO];

  LAAuthenticationView *laView = [[LAAuthenticationView alloc] initWithContext:self.context];
  [self.rootView addSubview:laView];
  self.rootView.translatesAutoresizingMaskIntoConstraints = NO;;
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers requestParameters:(ASPasskeyCredentialRequestParameters *) requestParameters {
  // TODO: This will be called for passkeys
}

- (void)prepareOneTimeCodeCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {}

- (void)prepareInterfaceForPasskeyRegistration:(id<ASCredentialRequest>) registrationRequest {  
  /*QWidget* widget = new CredentialListWidget(self.extensionContext);
  [self embedQWidget:widget hideRootView:NO];

  LAAuthenticationView *laView = [[LAAuthenticationView alloc] initWithContext:self.context];
  [self.rootView addSubview:laView];
  self.rootView.translatesAutoresizingMaskIntoConstraints = NO;;*/

  self.credentialRequest = registrationRequest;
}

- (void)prepareInterfaceToProvideCredentialForRequest:(id<ASCredentialRequest>) credentialRequest {
  /*LAAuthenticationView *laView = [[LAAuthenticationView alloc] initWithContext:self.context];
  laView.translatesAutoresizingMaskIntoConstraints = NO;

  QWidget* widget = new PasskeyConfirmationWidget(self.extensionContext, credentialRequest, laView, self.context);
  [self embedQWidget:widget hideRootView:NO];*/
  self.credentialRequest = credentialRequest;
}

- (void)provideCredentialWithoutUserInteractionForRequest:(id<ASCredentialRequest>) credentialRequest {
  [self exitWithUserInteractionRequired];
}

// - (void)performPasskeyRegistrationWithoutUserInteractionIfPossible:(ASPasskeyCredentialRequest *) registrationRequest {}

- (void)embedQWidget:(QWidget *)widget hideRootView:(BOOL)hide {
  NSView* rootView = reinterpret_cast<NSView *>(widget->winId());
  if (hide) {
    rootView.frame = NSMakeRect(0, 0, 0, 0);
  }

  [self.view addSubview:rootView];

  self.view.translatesAutoresizingMaskIntoConstraints = NO;

  [NSLayoutConstraint activateConstraints:@[
    [self.view.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:0],
    [self.view.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:0],
    [self.view.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:0],
    [self.view.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:0]
  ]];

  [self.view.widthAnchor constraintEqualToConstant:rootView.frame.size.width].active = YES;
  [self.view.heightAnchor constraintEqualToConstant:rootView.frame.size.height].active = YES;

  self.rootView = rootView;
}

- (void)prepareInterfaceForExtensionConfiguration {
  /*QWidget* widget = new ExtensionConfigurationWidget(self.extensionContext);

  [self embedQWidget:widget hideRootView:NO];*/
}

- (void)exitWithUserInteractionRequired {
  NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
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
