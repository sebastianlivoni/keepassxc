#include "AutoFillServiceV2.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <ServiceManagement/SMAppService.h>

#include "core/Tools.h"
#include "gui/DatabaseOpenWidget.h"
#include "gui/MainWindow.h"

#ifdef Q_OS_MACOS
#include "gui/osutils/macutils/MacUtils.h"
#endif

void AutoFillServiceV2::start() {
  NSError *agentError = nil;

  SMAppService *agentService = [SMAppService
      agentServiceWithPlistName:
          [NSString stringWithFormat:@"%@.plist", @RENDEZVOUS_APP_IDENTIFIER]];

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
  m_pendingPasswordIdentity = nil;
  m_pendingPasswordReplyBlock = nil;
  m_pendingOtpIdentity = nil;
  m_pendingOtpReplyBlock = nil;
}

void AutoFillServiceV2::fetchPasswordCredentialFromIdentity(
    ASPasswordCredentialIdentity *identity,
    void (^reply)(ASPasswordCredential *__strong credential,
                  NSError *__strong error)) {
  dispatch_async(dispatch_get_main_queue(), ^{
    QUuid dbUuid;
    QUuid entryUuid;
    if (!parseRecordIdentifier(identity.recordIdentifier, dbUuid, entryUuid)) {
      NSError *badIdError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                 code:400
                                             userInfo:nil];
      reply(nil, badIdError);
      return;
    }

    DatabaseWidget *targetWidget = findDatabaseWidgetByUuid(dbUuid);
    if (!targetWidget) {
      NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
      reply(nil, noDbError);
      return;
    }

    if (targetWidget->isLocked()) {
      m_pendingPasswordIdentity = identity;
      m_pendingPasswordReplyBlock = reply;
      m_pendingPasswordTargetWidget = targetWidget;

      bool triggerUnlock = true;
      openDatabase(triggerUnlock, targetWidget);

      return;
    }

    auto database = targetWidget->database();
    if (database.isNull()) {
      NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
      reply(nil, noDbError);
      return;
    }

    ASPasswordCredential *passwordCredential =
        getPasswordCredentialFromIdentity(identity, database);
    if (!passwordCredential) {
      NSError *notFoundError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                     code:404
                                                 userInfo:nil];
      reply(nil, notFoundError);
      return;
    }

    reply(passwordCredential, nil);
  });
}

void AutoFillServiceV2::fetchOneTimeCodeForIdentity(
    ASOneTimeCodeCredentialIdentity *identity,
    void (^reply)(ASOneTimeCodeCredential *__strong credential,
                  NSError *__strong error)) {
  dispatch_async(dispatch_get_main_queue(), ^{
    QUuid dbUuid;
    QUuid entryUuid;
    if (!parseRecordIdentifier(identity.recordIdentifier, dbUuid, entryUuid)) {
      NSError *badIdError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                 code:400
                                             userInfo:nil];
      reply(nil, badIdError);
      return;
    }

    DatabaseWidget *targetWidget = findDatabaseWidgetByUuid(dbUuid);
    if (!targetWidget) {
      NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
      reply(nil, noDbError);
      return;
    }

    if (targetWidget->isLocked()) {
      m_pendingOtpIdentity = identity;
      m_pendingOtpReplyBlock = reply;
      m_pendingOtpTargetWidget = targetWidget;

      bool triggerUnlock = true;
      openDatabase(triggerUnlock, targetWidget);

      return;
    }

    auto database = targetWidget->database();
    if (database.isNull()) {
      NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
      reply(nil, noDbError);
      return;
    }

    ASOneTimeCodeCredential *oneTimeCredential =
        getOneTimeCodeCredentialFromIdentity(identity, database);
    if (!oneTimeCredential) {
      NSError *notFoundError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                     code:404
                                                 userInfo:nil];
      reply(nil, notFoundError);
      return;
    }

    reply(oneTimeCredential, nil);
  });
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

      ASPasskeyRegistrationCredential *credential =
          createPasskeyRegistrationCredential(request, database);

      reply(credential, nil);
      return;
    }
  }
}

bool AutoFillServiceV2::openDatabase(bool triggerUnlock,
                                     DatabaseWidget *targetWidget) {
  auto *window = getMainWindow();
  if (!window)
    return false;

  if (!targetWidget) {
    targetWidget = m_currentDatabaseWidget;
  }
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
    emit requestUnlock(targetWidget);
  }

  return false;
}

void AutoFillServiceV2::updateWindowState() {
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

void AutoFillServiceV2::hideWindow() const {
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

void AutoFillServiceV2::activeDatabaseChanged(DatabaseWidget *dbWidget) {
  m_currentDatabaseWidget = dbWidget;
}

void AutoFillServiceV2::fetchPasskeyCredentialFromPasskeyRequest(
    ASPasskeyCredentialRequest *request,
    void (^reply)(ASPasskeyAssertionCredential *__strong credential,
                  NSError *__strong error)) {
  dispatch_async(dispatch_get_main_queue(), ^{
    ASPasskeyCredentialIdentity *identity =
        static_cast<ASPasskeyCredentialIdentity *>(request.credentialIdentity);

    QUuid dbUuid;
    QUuid entryUuid;
    if (!parseRecordIdentifier(identity.recordIdentifier, dbUuid, entryUuid)) {
      NSError *badIdError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                 code:400
                                             userInfo:nil];
      reply(nil, badIdError);
      return;
    }

    DatabaseWidget *targetWidget = findDatabaseWidgetByUuid(dbUuid);
    if (!targetWidget) {
      NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
      reply(nil, noDbError);
      return;
    }

    if (targetWidget->isLocked()) {
      m_pendingRequest = request;
      m_pendingReplyBlock = reply;
      m_pendingPasskeyTargetWidget = targetWidget;

      bool triggerUnlock = true;
      openDatabase(triggerUnlock, targetWidget);

      return;
    }

    auto database = targetWidget->database();
    if (database.isNull()) {
      NSError *noDbError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
      reply(nil, noDbError);
      return;
    }

    ASPasskeyAssertionCredential *credential =
        getPasskeyCredentialFromPasskeyRequest(request, database);
    if (!credential) {
      NSError *notFoundError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                     code:404
                                                 userInfo:nil];
      reply(nil, notFoundError);
      return;
    }

    reply(credential, nil);
  });
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

  connect(getMainWindow(), &MainWindow::activeDatabaseChanged, this,
          &AutoFillServiceV2::activeDatabaseChanged);
  connect(getMainWindow(), &MainWindow::databaseUnlocked, this,
          &AutoFillServiceV2::databaseUnlocked);
  connect(getMainWindow(), &MainWindow::databaseUnlockDialogFinished, this,
          &AutoFillServiceV2::databaseUnlockDialogFinished);

  m_signalsConnected = true;
}

DatabaseWidget *
AutoFillServiceV2::findDatabaseWidgetByUuid(const QUuid &dbUuid) const {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget) {
        continue;
      }
      auto database = widget->database();
      if (!database.isNull() && database->publicUuid() == dbUuid) {
        return widget;
      }
    }
  }
  return nullptr;
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

void AutoFillServiceV2::refreshIdentityStore() { replaceCredentialStore(); }

void AutoFillServiceV2::saveCredentialStore(
    const QSharedPointer<Database> &db) {}

static void logIfFailed(BOOL success, NSError *error, NSString *what) {
  if (!success) {
    NSLog(@"AutoFill: failed to %@: %@", what, error.localizedDescription);
  }
}

void AutoFillServiceV2::replaceCredentialStore() {
  auto *window = getMainWindow();
  if (!window) {
    return;
  }

  [ASCredentialIdentityStore.sharedStore
      getCredentialIdentityStoreStateWithCompletion:^(
          ASCredentialIdentityStoreState *state) {
        if (!state.isEnabled) {
          return;
        }

        // Compute fresh identities for every currently open & unlocked
        // database up front, keyed by database UUID. Locked or
        // not-currently-open databases are simply absent here, and are
        // never touched below, so their previously-published suggestions
        // keep working until they're opened again.
        NSMutableDictionary<NSString *, NSArray *> *freshIdentitiesByDb =
            [NSMutableDictionary dictionary];

        for (auto *widget : window->getOpenDatabases()) {
          if (!widget || widget->isLocked()) {
            continue;
          }
          auto db = widget->database();
          if (db.isNull()) {
            continue;
          }

          QUuid publicUuid = db->publicUuid();
          NSString *dbKey = Tools::uuidToHex(publicUuid).toNSString();

          NSMutableArray *credentialIdentities = [NSMutableArray array];

          for (Entry *entry : db->rootGroup()->entriesRecursive()) {
            if (entry->isRecycled()) {
              continue;
            }

            auto *passwordCredentialIdentity =
                getPasswordCredentialIdentityFromEntry(entry, publicUuid, widget->displayName());

            if (passwordCredentialIdentity) {
              [credentialIdentities addObject:passwordCredentialIdentity];
            }

            auto *oneTimeCodeCredentialIdentity =
                getOneTimeCodeCredentialIdentityFromEntry(entry, publicUuid);

            if (oneTimeCodeCredentialIdentity) {
              [credentialIdentities addObject:oneTimeCodeCredentialIdentity];
            }

            auto *passkeyCredentialIdentity =
                getPasskeyCredentialIdentityFromEntry(entry, publicUuid);

            if (passkeyCredentialIdentity) {
              [credentialIdentities addObject:passkeyCredentialIdentity];
            }
          }

          freshIdentitiesByDb[dbKey] = credentialIdentities;
        }

        if (freshIdentitiesByDb.count == 0) {
          return;
        }

        if (@available(macOS 14.4, *)) {
          // Ask the store what it already has, so we know exactly what's
          // stale for the databases we're refreshing, and exactly what
          // belongs to other databases that must be left untouched.
          [ASCredentialIdentityStore.sharedStore
              getCredentialIdentitiesForService:nil
                        credentialIdentityTypes:ASCredentialIdentityTypesAll
                              completionHandler:^(
                                  NSArray<id<ASCredentialIdentity>> *existingIdentities) {
                NSMutableDictionary<NSString *, NSMutableArray *> *existingByDb =
                    [NSMutableDictionary dictionary];
                NSMutableArray *otherDatabasesIdentities = [NSMutableArray array];

                for (id<ASCredentialIdentity> identity in existingIdentities) {
                  QUuid dbUuid;
                  QUuid entryUuid;
                  NSString *dbKey =
                      parseRecordIdentifier(identity.recordIdentifier, dbUuid, entryUuid)
                          ? Tools::uuidToHex(dbUuid).toNSString()
                          : nil;

                  if (dbKey && freshIdentitiesByDb[dbKey]) {
                    NSMutableArray *bucket = existingByDb[dbKey];
                    if (!bucket) {
                      bucket = [NSMutableArray array];
                      existingByDb[dbKey] = bucket;
                    }
                    [bucket addObject:identity];
                  } else {
                    [otherDatabasesIdentities addObject:identity];
                  }
                }

                if (state.supportsIncrementalUpdates) {
                  // A rename (entry title, database display name, username,
                  // URL...) never changes an identity's recordIdentifier
                  // (it's derived only from the entry/database UUIDs), so a
                  // key-based diff would treat the renamed identity as
                  // "unchanged" and skip removing it — but saving a new
                  // identity object under the same recordIdentifier isn't
                  // reliably picked up as an in-place update by the system.
                  // So for every database being refreshed, unconditionally
                  // drop whatever it currently has in the store and save
                  // the fresh set — guaranteeing stale/renamed entries are
                  // actually gone, not just shadowed by a newer one.
                  [freshIdentitiesByDb
                      enumerateKeysAndObjectsUsingBlock:^(
                          NSString *dbKey, NSArray *freshIdentities, BOOL *) {
                        NSArray *existingForDb = existingByDb[dbKey];
                        if (existingForDb.count > 0) {
                          [ASCredentialIdentityStore.sharedStore
                              removeCredentialIdentityEntries:existingForDb
                                                    completion:^(BOOL success, NSError *error) {
                                                      logIfFailed(success, error,
                                                                  @"remove stale credential identities");
                                                    }];
                        }

                        [ASCredentialIdentityStore.sharedStore
                            saveCredentialIdentityEntries:freshIdentities
                                                completion:^(BOOL success, NSError *error) {
                                                  logIfFailed(success, error,
                                                              @"save credential identities");
                                                }];
                      }];
                } else {
                  // No incremental support: the only way to remove anything
                  // is a full replace, so fold in every other database's
                  // existing identities untouched to avoid erasing them.
                  NSMutableArray *combined = [otherDatabasesIdentities mutableCopy];
                  [freshIdentitiesByDb
                      enumerateKeysAndObjectsUsingBlock:^(NSString *, NSArray *freshIdentities,
                                                          BOOL *) {
                        [combined addObjectsFromArray:freshIdentities];
                      }];

                  [ASCredentialIdentityStore.sharedStore
                      replaceCredentialIdentityEntries:combined
                                             completion:^(BOOL success, NSError *error) {
                                               logIfFailed(success, error,
                                                           @"replace credential identities");
                                             }];
                }
              }];
        } else {
          // Can't inspect the store's existing contents on this OS version;
          // upsert-only so we never risk destroying data we can't see.
          [freshIdentitiesByDb
              enumerateKeysAndObjectsUsingBlock:^(NSString *, NSArray *freshIdentities, BOOL *) {
                [ASCredentialIdentityStore.sharedStore
                    saveCredentialIdentityEntries:freshIdentities
                                        completion:^(BOOL success, NSError *error) {
                                          logIfFailed(success, error, @"save credential identities");
                                        }];
              }];
        }
      }];
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

void AutoFillServiceV2::databaseUnlocked(DatabaseWidget *dbWidget) {
  if (!dbWidget)
    return;

  bool resolvedPendingRequest = false;
  auto database = dbWidget->database();

  if (m_pendingRequest && m_pendingReplyBlock &&
      dbWidget == m_pendingPasskeyTargetWidget) {
    if (!database.isNull()) {
      ASPasskeyAssertionCredential *credential =
          getPasskeyCredentialFromPasskeyRequest(m_pendingRequest, database);

      if (credential) {
        m_pendingReplyBlock(credential, nil);
      } else {
        NSError *failErr = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
        m_pendingReplyBlock(nil, failErr);
      }
    }

    m_pendingRequest = nil;
    m_pendingReplyBlock = nil;
    m_pendingPasskeyTargetWidget = nullptr;
    resolvedPendingRequest = true;
  }

  if (m_pendingPasswordIdentity && m_pendingPasswordReplyBlock &&
      dbWidget == m_pendingPasswordTargetWidget) {
    if (!database.isNull()) {
      ASPasswordCredential *credential = getPasswordCredentialFromIdentity(
          m_pendingPasswordIdentity, database);

      if (credential) {
        m_pendingPasswordReplyBlock(credential, nil);
      } else {
        NSError *failErr = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
        m_pendingPasswordReplyBlock(nil, failErr);
      }
    }

    m_pendingPasswordIdentity = nil;
    m_pendingPasswordReplyBlock = nil;
    m_pendingPasswordTargetWidget = nullptr;
    resolvedPendingRequest = true;
  }

  if (m_pendingOtpIdentity && m_pendingOtpReplyBlock &&
      dbWidget == m_pendingOtpTargetWidget) {
    if (!database.isNull()) {
      ASOneTimeCodeCredential *credential =
          getOneTimeCodeCredentialFromIdentity(m_pendingOtpIdentity, database);

      if (credential) {
        m_pendingOtpReplyBlock(credential, nil);
      } else {
        NSError *failErr = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                               code:404
                                           userInfo:nil];
        m_pendingOtpReplyBlock(nil, failErr);
      }
    }

    m_pendingOtpIdentity = nil;
    m_pendingOtpReplyBlock = nil;
    m_pendingOtpTargetWidget = nullptr;
    resolvedPendingRequest = true;
  }

  // A different database than the one we're waiting on may have unlocked
  // (e.g. the user opened another tab); keep waiting and keep the app in
  // front until the actual target database unlocks.
  if (resolvedPendingRequest && m_bringToFrontRequested) {
    m_bringToFrontRequested = false;
    hideWindow();
  }
}

void AutoFillServiceV2::databaseUnlockDialogFinished(bool accepted,
                                                     DatabaseWidget *dbWidget) {
  if (accepted) {
    // The corresponding databaseUnlocked() signal resolves the pending
    // request once the widget actually finishes unlocking.
    return;
  }

  bool cancelledPendingRequest = false;
  NSError *cancelledError = [NSError errorWithDomain:@"org.keepassxc.autofill"
                                                 code:1
                                             userInfo:nil];

  if (m_pendingRequest && m_pendingReplyBlock &&
      dbWidget == m_pendingPasskeyTargetWidget) {
    m_pendingReplyBlock(nil, cancelledError);
    m_pendingRequest = nil;
    m_pendingReplyBlock = nil;
    m_pendingPasskeyTargetWidget = nullptr;
    cancelledPendingRequest = true;
  }

  if (m_pendingPasswordIdentity && m_pendingPasswordReplyBlock &&
      dbWidget == m_pendingPasswordTargetWidget) {
    m_pendingPasswordReplyBlock(nil, cancelledError);
    m_pendingPasswordIdentity = nil;
    m_pendingPasswordReplyBlock = nil;
    m_pendingPasswordTargetWidget = nullptr;
    cancelledPendingRequest = true;
  }

  if (m_pendingOtpIdentity && m_pendingOtpReplyBlock &&
      dbWidget == m_pendingOtpTargetWidget) {
    m_pendingOtpReplyBlock(nil, cancelledError);
    m_pendingOtpIdentity = nil;
    m_pendingOtpReplyBlock = nil;
    m_pendingOtpTargetWidget = nullptr;
    cancelledPendingRequest = true;
  }

  if (cancelledPendingRequest && m_bringToFrontRequested) {
    m_bringToFrontRequested = false;
    hideWindow();
  }
}