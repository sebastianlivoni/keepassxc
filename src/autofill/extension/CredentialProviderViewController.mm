#include "extension/CredentialProviderViewController.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <QApplication>
#include <QtWidgets>
#include <QPushButton>
#include <QStackedWidget>
#include <QVBoxLayout>

#include "common/AutoFillCredentials.h"
#include "browser/BrowserPasskeysConfirmationDialog.h"
#include "extension/widgets/ConfigurationWidget.h"
#include "extension/widgets/CredentialListWidget.h"
#include "extension/widgets/DatabasePickerWidget.h"
#include "extension/widgets/DatabaseUnlockWidget.h"
#include "extension/widgets/PasskeyConfirmationWidget.h"
#include "extension/widgets/PasswordConfirmationWidget.h"
#include "extension/widgets/OneTimeCodeConfirmationWidget.h"

#include "core/Config.h"
#include "core/Entry.h"
#include "core/Tools.h"
#include "gui/DatabaseOpenWidget.h"
#include "quickunlock/QuickUnlockInterface.h"
#include "quickunlock/TouchID.h"

#include <os/log.h>

#include "helper/AutoFillHelperProtocol.h"
#include "common/AutoFillCodeSigning.h"
#include "extension/AutoFillExtensionApplication.h"

// No timeout comes with the request; 5 minutes like browsers' WebAuthn default
static const int PASSKEY_REGISTRATION_TIMEOUT_MS = 300000;

@interface CredentialProviderViewController ()

// The embedded Qt view, made first responder so it receives key events
@property(nonatomic, strong) NSView *rootView;
// Calls waiting for the endpoint lookup through the helper
@property(nonatomic, strong) NSMutableArray *pendingConnectionBlocks;
@property(nonatomic, assign) BOOL serviceConnectionResolved;
@property(nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property(nonatomic, strong) NSLayoutConstraint *heightConstraint;

@end

@implementation CredentialProviderViewController

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil
                         bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    // One Qt application per extension process, which may serve several requests
    if (!qApp) {
      // Use the Qt plugins bundled in the containing app (KeePassXC.app/Contents/PlugIns,
      // which also holds this .appex); dev builds without bundled plugins keep Qt's default
      NSString *appPlugIns =
          NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.path;
      if ([NSFileManager.defaultManager
              fileExistsAtPath:[appPlugIns stringByAppendingPathComponent:@"platforms"]]) {
        QCoreApplication::setLibraryPaths({QString::fromNSString(appPlugIns)});
      }

      // Qt keeps references to argc/argv for the application's lifetime
      static int argc = 0;
      static char *argv[] = {nullptr};
      new AutoFillExtensionApplication(argc, argv);
    }

    self.xpcClient = [[AutoFillXPCClient alloc] init];
    [self.xpcClient start];

    id proxy = [self.xpcClient.helperConnection
        remoteObjectProxyWithErrorHandler:^(NSError *error) {
          os_log_error(OS_LOG_DEFAULT,
                       "[AutoFill] Helper connection error: %{public}@",
                       error);
          [self resolveServiceConnection];
        }];

    [proxy getEndpoint:^(NSXPCListenerEndpoint *endpoint,
                                  NSError *error) {
      if (error) {
        os_log_error(OS_LOG_DEFAULT,
                     "[AutoFill] Failed to obtain service endpoint from "
                     "helper: %{public}@",
                     error);
        [self resolveServiceConnection];
        return;
      }

      self.xpcClient.connection =
          [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
      self.xpcClient.connection.remoteObjectInterface = AutoFillXPCInterface();
      [self.xpcClient.connection setCodeSigningRequirement:CodeSigningRequirement(@APPLE_APP_IDENTIFIER)];
      [self.xpcClient.connection resume];

      [self resolveServiceConnection];
    }];

  }
  return self;
}

- (void)viewDidAppear {
  [super viewDidAppear];
  [self focusEmbeddedWidget];

  return;
}

// Enabled in System Settings: have KeePassXC publish its identities right away
- (void)prepareInterfaceForExtensionConfiguration {
  [self withServiceConnection:^(NSXPCConnection *connection) {
    id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
      os_log_error(OS_LOG_DEFAULT, "[AutoFill] Republish request failed: %{public}@", error);
    }];
    [proxy republishCredentialIdentities];
  }];

  auto *widget = new ConfigurationWidget();
  __weak CredentialProviderViewController *weakSelf = self;
  widget->onDone = [weakSelf]() {
    [weakSelf.extensionContext completeExtensionConfigurationRequest];
  };
  [self embedQWidget:widget];
}

- (void)prepareCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
  auto *widget = new CredentialListWidget(
      self.extensionContext, serviceIdentifiers,
      CredentialListWidget::Mode::Password);
  [self embedCredentialListWidget:widget];
}

- (void)prepareCredentialListForServiceIdentifiers:
            (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers
                                 requestParameters:
                                     (ASPasskeyCredentialRequestParameters *)
                                         requestParameters {
  auto *widget = new CredentialListWidget(
      self.extensionContext, requestParameters);
  [self embedCredentialListWidget:widget];
}

- (void)prepareOneTimeCodeCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
  auto *widget = new CredentialListWidget(
      self.extensionContext, serviceIdentifiers,
      CredentialListWidget::Mode::TOTP);
  [self embedCredentialListWidget:widget];
}

- (void)prepareInterfaceForPasskeyRegistration:
    (id<ASCredentialRequest>)registrationRequest {
  ASPasskeyCredentialRequest *passkeyRequest =
      static_cast<ASPasskeyCredentialRequest *>(registrationRequest);
  ASPasskeyCredentialIdentity *identity =
      static_cast<ASPasskeyCredentialIdentity *>(
          passkeyRequest.credentialIdentity);

  QString relyingParty =
      QString::fromNSString(identity.relyingPartyIdentifier);
  QString username = QString::fromNSString(identity.userName);

  auto *stack = new QStackedWidget();
  stack->resize(480, 420);

  // confirm(existingEntryUuid) registers the passkey; a null UUID creates a new entry
  auto showRegistrationDialog = [self, stack, relyingParty, username](
                                    const QList<Entry *> &existingEntries,
                                    std::function<void(const QUuid &)> confirm) {
    // The browser integration's dialog, embedded instead of shown as a window
    auto *dialog = new BrowserPasskeysConfirmationDialog();
    dialog->setWindowFlags(Qt::Widget);
    dialog->registerCredential(username, relyingParty, existingEntries, PASSKEY_REGISTRATION_TIMEOUT_MS);
    // "Add to existing entry" opens the browser's passkey importer, which isn't available here
    if (existingEntries.isEmpty()) {
      if (auto *updateButton = dialog->findChild<QPushButton *>("updateButton")) {
        updateButton->hide();
      }
    }
    QObject::connect(dialog, &QDialog::accepted, dialog, [self, dialog, confirm]() {
      if (!dialog->isPasskeyUpdated()) {
        confirm(QUuid());
      } else if (Entry *selectedEntry = dialog->getSelectedEntry()) {
        confirm(selectedEntry->uuid());
      } else {
        [self exitCancelRequest];
      }
    });
    QObject::connect(dialog, &QDialog::rejected, dialog, [self]() { [self exitCancelRequest]; });

    // Same size as the browser dialog: 400x274 from the .ui, or fixed to content
    dialog->layout()->activate();
    const QSize size = dialog->size().expandedTo(dialog->minimumSizeHint());
    stack->addWidget(dialog);
    stack->setCurrentWidget(dialog);

    // Drop picker/unlock pages so their minimum size doesn't block the resize;
    // deleteLater since we may be called from inside the unlock widget
    while (stack->count() > 1) {
      QWidget *page =
          stack->widget(0) == dialog ? stack->widget(1) : stack->widget(0);
      stack->removeWidget(page);
      page->deleteLater();
    }
    stack->layout()->activate();
    [self resizeEmbeddedWidget:stack toSize:size];
  };

  // Database unlocked here in the extension
  auto registerLocally = [self, passkeyRequest, relyingParty,
                          showRegistrationDialog](QSharedPointer<Database> db) {
    const auto existingEntries = autoFillCredentials()->searchEntries(
        db, relyingParty, /*passkeyOnly=*/true, /*totpOnly=*/false);
    showRegistrationDialog(existingEntries, [self, passkeyRequest, db](const QUuid &entryUuid) {
      Entry *existingEntry =
          entryUuid.isNull() ? nullptr : db->rootGroup()->findEntryByUuid(entryUuid);
      ASPasskeyCredentialIdentity *previousIdentity =
          existingEntry ? autoFillCredentials()->getPasskeyCredentialIdentityFromEntry(
                              existingEntry, db->publicUuid())
                        : nil;
      Entry *registeredEntry = nullptr;
      ASPasskeyRegistrationCredential *credential =
          autoFillCredentials()->createPasskeyRegistrationCredential(
              passkeyRequest, db, existingEntry, /*saveDatabase=*/true, &registeredEntry);
      if (!credential) {
        [self exitCancelRequest];
        return;
      }
      // KeePassXC isn't involved here, so publish the new passkey ourselves
      [self savePasskeyIdentity:autoFillCredentials()->getPasskeyCredentialIdentityFromEntry(
                                    registeredEntry, db->publicUuid())
                      replacing:previousIdentity
                     completion:^{ [self completeRegistration:credential]; }];
    });
  };

  auto unlockInExtension = [self, stack, registerLocally](QString dbPath) {
    auto *unlockWidget =
        new DatabaseUnlockWidget(self.extensionContext, dbPath, stack);
    unlockWidget->onUnlocked = registerLocally;
    stack->addWidget(unlockWidget);
    stack->setCurrentWidget(unlockWidget);

    // Before embedding (single database) this sets the initial size
    [self resizeEmbeddedWidget:stack
                        toSize:stack->size().expandedTo(unlockWidget->size())];
  };

  // Database already unlocked in KeePassXC: register there over XPC (like
  // assertion) instead of unlocking it again here
  auto useDatabasePath = [self, stack, passkeyRequest, showRegistrationDialog,
                          unlockInExtension](QString dbPath) {
    const QString dbUuid = config()->getAllDatabaseFilePaths().key(dbPath);
    [self withServiceConnection:^(NSXPCConnection *connection) {
      if (!connection || dbUuid.isEmpty()) {
        unlockInExtension(dbPath);
        return;
      }
      id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        os_log_error(OS_LOG_DEFAULT, "[AutoFill] AutoFill service connection error: %{public}@", error);
        dispatch_async(dispatch_get_main_queue(), ^{ unlockInExtension(dbPath); });
      }];
      [proxy fetchExistingPasskeysForRegistrationRequest:passkeyRequest
                                            databaseUuid:dbUuid.toNSString()
                                               withReply:^(NSArray<NSArray<NSString *> *> *entries, NSError *) {
        dispatch_async(dispatch_get_main_queue(), ^{
          // Not open or locked in KeePassXC
          if (!entries) {
            unlockInExtension(dbPath);
            return;
          }
          // Stand-ins for KeePassXC's entries, only for display and selection in the dialog
          QList<Entry *> existingEntries;
          for (NSArray<NSString *> *fields in entries) {
            if (fields.count == 3) {
              auto *entry = new Entry();
              entry->QObject::setParent(stack);
              entry->setUuid(Tools::hexToUuid(QString::fromNSString(fields[0])));
              entry->setTitle(QString::fromNSString(fields[1]));
              entry->setUsername(QString::fromNSString(fields[2]));
              existingEntries.append(entry);
            }
          }
          showRegistrationDialog(existingEntries, [self, passkeyRequest, connection, dbUuid,
                                                    dbPath, unlockInExtension](const QUuid &entryUuid) {
            // KeePassXC closed or locked the database since the dialog was shown:
            // unlock here and show the dialog again from the database file
            id registerProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
              os_log_error(OS_LOG_DEFAULT, "[AutoFill] AutoFill service connection error: %{public}@", error);
              dispatch_async(dispatch_get_main_queue(), ^{ unlockInExtension(dbPath); });
            }];
            [registerProxy registerPasskeyForRequest:passkeyRequest
                                        databaseUuid:dbUuid.toNSString()
                                   existingEntryUuid:entryUuid.isNull() ? @"" : Tools::uuidToHex(entryUuid).toNSString()
                                           withReply:^(ASPasskeyRegistrationCredential *credential, NSError *error) {
              dispatch_async(dispatch_get_main_queue(), ^{
                if (!credential && [error.domain isEqualToString:@"org.keepassxc.autofill"] && error.code == 404) {
                  unlockInExtension(dbPath);
                  return;
                }
                [self completeRegistration:credential];
              });
            }];
          });
        });
      }];
    }];
  };

  const auto databasePaths = config()->getAllDatabaseFilePaths();
  if (databasePaths.isEmpty()) {
    [self exitCancelRequest];
    return;
  }

  if (databasePaths.size() == 1) {
    useDatabasePath(databasePaths.constBegin().value());
  } else {
    auto *picker = new DatabasePickerWidget(stack);
    picker->onDatabaseChosen = useDatabasePath;
    picker->onCancelled = [self]() { [self exitCancelRequest]; };
    stack->addWidget(picker);
    stack->setCurrentWidget(picker);
  }

  [self embedQWidget:stack];
}

// Calls completion once the store is updated; the extension may end right after
- (void)savePasskeyIdentity:(ASPasskeyCredentialIdentity *)identity
                  replacing:(ASPasskeyCredentialIdentity *)previousIdentity
                 completion:(void (^)(void))completion {
  void (^finish)(void) = ^{ dispatch_async(dispatch_get_main_queue(), completion); };
  void (^save)(void) = ^{
    if (!identity) {
      finish();
      return;
    }
    [ASCredentialIdentityStore.sharedStore
        saveCredentialIdentityEntries:@[ identity ]
                           completion:^(BOOL success, NSError *error) {
                             if (!success) {
                               NSLog(@"[AutoFill] Failed to save passkey identity: %@", error);
                             }
                             finish();
                           }];
  };

  if (!previousIdentity) {
    save();
    return;
  }
  [ASCredentialIdentityStore.sharedStore
      removeCredentialIdentityEntries:@[ previousIdentity ]
                           completion:^(BOOL success, NSError *error) {
                             if (!success) {
                               NSLog(@"[AutoFill] Failed to remove replaced passkey identity: %@", error);
                             }
                             save();
                           }];
}

- (void)completeRegistration:(ASPasskeyRegistrationCredential *)credential {
  if (!credential) {
    [self exitCancelRequest];
    return;
  }
  [self.extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:credential
                                                                 completionHandler:nil];
}

- (void)prepareInterfaceToProvideCredentialForRequest:
    (id<ASCredentialRequest>)credentialRequest {
  // With our UI showing, KeePassXC may ask for approval itself; fall back to
  // unlocking here if it can't provide the credential
  [self fetchCredentialForRequest:credentialRequest
                      interactive:YES
                            reply:^(id credential, NSError *error) {
                              if (credential) {
                                [self completeRequest:credentialRequest withCredential:credential];
                              } else if ([self isCancelledError:error]) {
                                [self exitCancelRequest];
                              } else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                  [self showConfirmationForRequest:credentialRequest];
                                });
                              }
                            }];
}

- (void)provideCredentialWithoutUserInteractionForRequest:
    (id<ASCredentialRequest>)credentialRequest {
  [self fetchCredentialForRequest:credentialRequest
                      interactive:NO
                            reply:^(id credential, NSError *error) {
                              if (credential) {
                                [self completeRequest:credentialRequest withCredential:credential];
                              } else if ([self isCancelledError:error]) {
                                [self exitCancelRequest];
                              } else {
                                // Not open in KeePassXC, entry not found or approval required (401):
                                // let the system show our UI
                                [self exitWithUserInteractionRequired];
                              }
                            }];
}

// A picked credential: try Touch ID with only the system prompt, and show the
// unlock UI if it isn't available, fails or is cancelled
- (void)showConfirmationForRequest:(id<ASCredentialRequest>)credentialRequest {
  ConfirmationWidget *widget = nullptr;
  switch (credentialRequest.type) {
  case ASCredentialRequestTypePassword:
    widget = new PasswordConfirmationWidget(self.extensionContext, credentialRequest);
    break;
  case ASCredentialRequestTypeOneTimeCode:
    widget = new OneTimeCodeConfirmationWidget(self.extensionContext, credentialRequest);
    break;
  case ASCredentialRequestTypePasskeyAssertion:
    widget = new PasskeyConfirmationWidget(self.extensionContext, credentialRequest);
    break;
  default:
    return;
  }
  if (widget->tryQuickUnlock()) {
    return;
  }
  [self embedQWidget:widget];
}

// Unlock was cancelled in KeePassXC: honour that instead of showing our UI
- (BOOL)isCancelledError:(NSError *)error {
  return [error.domain isEqualToString:@"org.keepassxc.autofill"] && error.code == 1;
}

// Asks KeePassXC for the credential; replies (nil, nil) without a connection
- (void)fetchCredentialForRequest:(id<ASCredentialRequest>)credentialRequest
                      interactive:(BOOL)interactive
                            reply:(void (^)(id credential, NSError *error))reply {
  [self withServiceConnection:^(NSXPCConnection *connection) {
    if (!connection) {
      reply(nil, nil);
      return;
    }
    id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *_Nonnull error) {
      os_log_error(OS_LOG_DEFAULT,
                   "[AutoFill] AutoFill service connection error: %{public}@. Main app likely closed.",
                   error);
      reply(nil, error);
    }];

    switch (credentialRequest.type) {
    case ASCredentialRequestTypePassword: {
      [proxy fetchPasswordCredentialForIdentity:static_cast<ASPasswordCredentialIdentity *>(
                                                     credentialRequest.credentialIdentity)
                                     interactive:interactive
                                       withReply:^(ASPasswordCredential *credential, NSError *error) {
                                         reply(credential, error);
                                       }];
      break;
    }
    case ASCredentialRequestTypeOneTimeCode: {
      [proxy fetchOneTimeCodeForIdentity:static_cast<ASOneTimeCodeCredentialIdentity *>(
                                             credentialRequest.credentialIdentity)
                             interactive:interactive
                               withReply:^(ASOneTimeCodeCredential *credential, NSError *error) {
                                 reply(credential, error);
                               }];
      break;
    }
    case ASCredentialRequestTypePasskeyAssertion: {
      [proxy fetchPasskeyCredentialFromPasskeyRequest:static_cast<ASPasskeyCredentialRequest *>(
                                                          credentialRequest)
                                          interactive:interactive
                                            withReply:^(ASPasskeyAssertionCredential *credential, NSError *error) {
                                              reply(credential, error);
                                            }];
      break;
    }
    default:
      reply(nil, nil);
      break;
    }
  }];
}

- (void)completeRequest:(id<ASCredentialRequest>)credentialRequest withCredential:(id)credential {
  switch (credentialRequest.type) {
  case ASCredentialRequestTypePassword:
    [self.extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
    break;
  case ASCredentialRequestTypeOneTimeCode:
    [self.extensionContext completeOneTimeCodeRequestWithSelectedCredential:credential
                                                          completionHandler:nil];
    break;
  case ASCredentialRequestTypePasskeyAssertion:
    [self.extensionContext completeAssertionRequestWithSelectedPasskeyCredential:credential
                                                               completionHandler:nil];
    break;
  default:
    [self exitCancelRequest];
    break;
  }
}

// Runs block once the direct connection to KeePassXC is known (nil if the
// endpoint lookup failed), so early requests don't message a nil connection
- (void)withServiceConnection:(void (^)(NSXPCConnection *connection))block {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.serviceConnectionResolved) {
      block(self.xpcClient.connection);
      return;
    }
    if (!self.pendingConnectionBlocks) {
      self.pendingConnectionBlocks = [NSMutableArray array];
    }
    [self.pendingConnectionBlocks addObject:[block copy]];
  });
}

- (void)resolveServiceConnection {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.serviceConnectionResolved) {
      return;
    }
    self.serviceConnectionResolved = YES;
    NSArray *blocks = self.pendingConnectionBlocks;
    self.pendingConnectionBlocks = nil;
    for (void (^block)(NSXPCConnection *) in blocks) {
      block(self.xpcClient.connection);
    }
  });
}

- (void)embedQWidget:(QWidget *)widget {
  widget->show();

  NSView *rootView = (__bridge NSView *)reinterpret_cast<void *>(widget->winId());

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

  self.widthConstraint = [self.view.widthAnchor
      constraintEqualToConstant:rootView.frame.size.width];
  self.heightConstraint = [self.view.heightAnchor
      constraintEqualToConstant:rootView.frame.size.height];
  self.widthConstraint.active = YES;
  self.heightConstraint.active = YES;

  self.rootView = rootView;
  [self focusEmbeddedWidget];
}

// Qt only receives key events once its view is first responder; otherwise
// typing does nothing until the sheet is clicked
- (void)focusEmbeddedWidget {
  if (self.rootView && self.view.window) {
    [self.view.window makeFirstResponder:self.rootView];
  }
}

- (void)embedCredentialListWidget:(CredentialListWidget *)widget {
  __weak CredentialProviderViewController *weakSelf = self;
  widget->onResizeRequested = [weakSelf, widget](QSize size) {
    [weakSelf resizeEmbeddedWidget:widget toSize:size];
  };
  [self embedQWidget:widget];
}

- (void)resizeEmbeddedWidget:(QWidget *)widget toSize:(QSize)size {
  widget->resize(size);
  self.widthConstraint.constant = size.width();
  self.heightConstraint.constant = size.height();
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
