#include "AutoFillServiceV2.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <ServiceManagement/SMAppService.h>

#include "gui/MainWindow.h"
#include "gui/DatabaseOpenWidget.h"

#ifdef Q_OS_MACOS
#include "gui/osutils/macutils/MacUtils.h"
#endif

void AutoFillServiceV2::start() {
  NSError *agentError = nil;

  SMAppService *agentService = [SMAppService
      agentServiceWithPlistName:[NSString stringWithFormat:@"%@.plist", @RENDEZVOUS_APP_IDENTIFIER]];

  BOOL agentRegistered = [agentService registerAndReturnError:&agentError];

  if (!agentRegistered) {
    NSLog(@"Failed to register agent service: %@", agentError);
  } else {
    NSLog(@"Successfully registered agent service");
  }

  AutoFillXPCService *service = [[AutoFillXPCService alloc] init];
  [service start];
  m_xpcService = service;

  connectSignals();
}

AutoFillServiceV2 *AutoFillServiceV2::instance() {
  static AutoFillServiceV2 *s_instance = new AutoFillServiceV2();
  return s_instance;
}

AutoFillServiceV2::~AutoFillServiceV2() {
  m_xpcService = nil;
  m_pendingRequest = nil;
  m_pendingReplyBlock = nil;
}

void AutoFillServiceV2::fetchPasswordCredentialFromIdentity(
    ASPasswordCredentialIdentity *identity,
    void (^reply)(ASPasswordCredential *__strong credential,
                  NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASPasswordCredential *passwordCredential =
          getPasswordCredentialFromIdentity(identity, database);

      reply(passwordCredential, nil);
      return;
    }
  }
}

void AutoFillServiceV2::fetchOneTimeCodeForIdentity(
    ASOneTimeCodeCredentialIdentity *identity,
    void (^reply)(ASOneTimeCodeCredential *__strong credential,
                  NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASOneTimeCodeCredential *oneTimeCredential =
          getOneTimeCodeCredentialFromIdentity(identity, database);

      reply(oneTimeCredential, nil);
      return;
    }
  }
}

void AutoFillServiceV2::createPasskeyRegistrationCredentialRequest(
    ASPasskeyCredentialRequest *request,
    void (^reply)(ASPasskeyRegistrationCredential *__strong credential,
                  NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASPasskeyRegistrationCredential *credential = createPasskeyRegistrationCredential(request, database);

      reply(credential, nil);
      return;
    }
  }
}

bool AutoFillServiceV2::openDatabase(bool triggerUnlock) {
  auto *window = getMainWindow();
  if (!window) return false;

  DatabaseWidget* targetWidget = m_currentDatabaseWidget;
  if (!targetWidget) {
      auto openDbs = window->getOpenDatabases();
      if (!openDbs.isEmpty()) {
          targetWidget = openDbs.first();
      }
  }

  if (targetWidget && !targetWidget->isLocked()) {
      return true;
  }

  if (triggerUnlock && !m_bringToFrontRequested) {
      m_bringToFrontRequested = true;
      updateWindowState();
      emit requestUnlock();
  }

  return false;
}

void AutoFillServiceV2::updateWindowState()
{
    m_prevWindowState = WindowState::Normal;
    if (getMainWindow()->isMinimized()) {
        m_prevWindowState = WindowState::Minimized;
    }
#ifdef Q_OS_MACOS
    if (macUtils()->isHidden()) {
        m_prevWindowState = WindowState::Hidden;
    }
#else
    if (getMainWindow()->isHidden()) {
        m_prevWindowState = WindowState::Hidden;
    }
#endif
}

void AutoFillServiceV2::hideWindow() const
{
    if (m_prevWindowState == WindowState::Minimized) {
        getMainWindow()->showMinimized();
    } else {
#ifdef Q_OS_MACOS
        if (m_prevWindowState == WindowState::Hidden) {
            macUtils()->hideOwnWindow();
        } else {
            macUtils()->raiseLastActiveWindow();
        }
#else
        if (m_prevWindowState == WindowState::Hidden) {
            getMainWindow()->hideWindow();
        } else {
            getMainWindow()->lower();
        }
#endif
    }
}

void AutoFillServiceV2::activeDatabaseChanged(DatabaseWidget* dbWidget)
{
  m_currentDatabaseWidget = dbWidget;
}

void AutoFillServiceV2::fetchPasskeyCredentialFromPasskeyRequest(
    ASPasskeyCredentialRequest *request,
    void (^reply)(ASPasskeyAssertionCredential *__strong credential,
                  NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        // TODO: This will toggle window multiple times if multiple opened database
        //QMetaObject::invokeMethod(window, "bringToFront", Qt::QueuedConnection);
        // TODO: window->bringToFront() does not work in this thread so I think we need to call it on main thread
        // Open app if closed maybe this can work within the autofillextension
        /*#include <AppKit/AppKit.h>

        /*QTimer::singleShot(0, window, [window]() {
          window->bringToFront();
        });*/


        /*QTimer::singleShot(0, window, [widget, window]() {
          if (widget->m_databaseOpenWidget->canPerformQuickUnlock()) {
            widget->m_databaseOpenWidget->triggerQuickUnlock();
          } else {
            window->bringToFront();
          }
        });*/

        m_pendingRequest = request;
        m_pendingReplyBlock = reply;

        bool triggerUnlock = true;
        openDatabase(triggerUnlock);

        /*QMetaObject::invokeMethod(window, [window, widget]() {
            //window->bringToFront();
            
            widget->m_databaseOpenWidget->triggerQuickUnlock();
        }, Qt::QueuedConnection);*/

        return;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASPasskeyAssertionCredential *credential =
          getPasskeyCredentialFromPasskeyRequest(request, database);

      reply(credential, nil);
      return;
    }
  }

  NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill" code:404 userInfo:nil];
  reply(nil, noDbError);
}

void AutoFillServiceV2::connectSignals() {
  if (m_signalsConnected) {
    return;
  }

  if (auto *window = getMainWindow()) {
    connect(window, &MainWindow::databaseUnlocked, this,
            [this](DatabaseWidget *widget) {
              watchDatabase(widget);
              refreshIdentityStore();
            });
    connect(window, &MainWindow::databaseLocked, this,
            [this](DatabaseWidget *widget) {
              m_watchedDatabases.remove(widget);
              refreshIdentityStore();
            });
    connect(window, &MainWindow::activeDatabaseChanged, this,
            [this](DatabaseWidget *) { refreshIdentityStore(); });
  }

  connect(getMainWindow(), &MainWindow::databaseUnlocked, this, &AutoFillServiceV2::databaseUnlocked);

  m_signalsConnected = true;
}

void AutoFillServiceV2::watchDatabase(DatabaseWidget *widget) {
  if (!widget || m_watchedDatabases.contains(widget)) {
    return;
  }

  m_watchedDatabases.insert(widget);

  connect(widget, &DatabaseWidget::databaseModified, this,
          [this]() { refreshIdentityStore(); });
  connect(widget, &DatabaseWidget::databaseSaved, this,
          [this]() { refreshIdentityStore(); });
  connect(widget, &DatabaseWidget::databaseReplaced, this,
          [this](const QSharedPointer<Database> &,
                 const QSharedPointer<Database> &) { refreshIdentityStore(); });
  connect(widget, &DatabaseWidget::databaseLocked, this, [this, widget]() {
    m_watchedDatabases.remove(widget);
    refreshIdentityStore();
  });
  /*connect(widget, &QObject::destroyed, this, [this, widget]() {
    m_watchedDatabases.remove(widget);
    refreshIdentityStore();
    });*/
}

void AutoFillServiceV2::refreshIdentityStore() {
  replaceCredentialStore();
}

void AutoFillServiceV2::saveCredentialStore(
    const QSharedPointer<Database> &db) {}

void AutoFillServiceV2::replaceCredentialStore() {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }
      auto db = widget->database();
      if (db.isNull()) {
        continue;
      }
      [ASCredentialIdentityStore
              .sharedStore getCredentialIdentityStoreStateWithCompletion:^(
                               ASCredentialIdentityStoreState *state) {
        if (state.isEnabled) {
          NSMutableArray *credentialIdentities = [NSMutableArray array];

          for (Entry *entry : db->rootGroup()->entriesRecursive()) {
            if (entry->isRecycled()) {
              continue;
            }

            auto *passwordCredentialIdentity =
                getPasswordCredentialIdentityFromEntry(entry);

            if (passwordCredentialIdentity) {
              [credentialIdentities addObject:passwordCredentialIdentity];
            }

            auto *oneTimeCodeCredentialIdentity =
                getOneTimeCodeCredentialIdentityFromEntry(entry);

            if (oneTimeCodeCredentialIdentity) {
              [credentialIdentities addObject:oneTimeCodeCredentialIdentity];
            }

            auto *passkeyCredentialIdentity =
                getPasskeyCredentialIdentityFromEntry(entry);

            if (passkeyCredentialIdentity) {
              [credentialIdentities addObject:passkeyCredentialIdentity];
            }
          }

          [ASCredentialIdentityStore.sharedStore
              replaceCredentialIdentityEntries:credentialIdentities
                                    completion:^(BOOL success, NSError *error) {
                                      if (success) {
                                        NSLog(@"Successfully replaced "
                                              @"credential identities. (%lu "
                                              @"items)",
                                              credentialIdentities.count);
                                      } else {
                                        NSLog(@"Failed to replace credential "
                                              @"identities: %@",
                                              error.localizedDescription);
                                      }
                                    }];
        }
      }];
    }
  }
}

void AutoFillServiceV2::resetCredentialStore() {
  [ASCredentialIdentityStore.sharedStore
      getCredentialIdentityStoreStateWithCompletion:^(
          ASCredentialIdentityStoreState *state) {
        if (state.isEnabled) {
          [ASCredentialIdentityStore.sharedStore
              removeAllCredentialIdentitiesWithCompletion:nil];
        }
      }];
}

void AutoFillServiceV2::databaseUnlocked(DatabaseWidget* dbWidget)
{
  if (!dbWidget) return;

  if (m_pendingRequest && m_pendingReplyBlock) {
    auto database = dbWidget->database();
      if (!database.isNull()) {
          ASPasskeyAssertionCredential *credential = getPasskeyCredentialFromPasskeyRequest(m_pendingRequest, database);
          
          if (credential) {
              m_pendingReplyBlock(credential, nil);
          } else {
              NSError *failErr = [NSError errorWithDomain:@"org.keepassxc.autofill" code:404 userInfo:nil];
              m_pendingReplyBlock(nil, failErr);
          }
      }
      
      m_pendingRequest = nil;
      m_pendingReplyBlock = nil;
  }

  if (m_bringToFrontRequested) {
    m_bringToFrontRequested = false;
    hideWindow();
  }
}