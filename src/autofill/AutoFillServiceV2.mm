#include "AutoFillServiceV2.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <ServiceManagement/SMAppService.h>

#include "../gui/MainWindow.h"

void AutoFillServiceV2::start() {
  NSError *agentError = nil;

  SMAppService *agentService = [SMAppService
      agentServiceWithPlistName:@"me.livoni.KeePassXC.AutoFillService.plist"];

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
  static AutoFillServiceV2 s_instance;
  return &s_instance;
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

void AutoFillServiceV2::fetchPasskeyCredentialFromPasskeyRequest(
    ASPasskeyCredentialRequest *request,
    void (^reply)(ASPasskeyAssertionCredential *__strong credential,
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

      ASPasskeyAssertionCredential *credential =
          getPasskeyCredentialFromPasskeyRequest(request, database);

      reply(credential, nil);
      return;
    }
  }
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
