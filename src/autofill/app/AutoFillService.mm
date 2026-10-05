#include "app/AutoFillService.h"
#include "app/AutoFillXPCListener.h"
#include "common/AutoFillBookmarks.h"
#include "common/AutoFillDatabaseOptions.h"
#include "common/AutoFillSupport.h"
#include "common/AutoFillXPCProtocol.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <LocalAuthentication/LocalAuthentication.h>

#include <QApplication>
#include <QCoreApplication>
#include <QDateTime>
#include <QPointer>
#include <memory>

#include "core/Config.h"
#include "core/Tools.h"
#include "gui/DatabaseOpenWidget.h"
#include "gui/MainWindow.h"

#include "gui/osutils/macutils/MacUtils.h"

using namespace AutoFillCredentials;

struct AutoFillService::Private
{
    // A request waiting for its database to be unlocked in KeePassXC
    struct PendingRequest
    {
        QPointer<DatabaseWidget> target;
        CredentialMaker makeCredential;
        CredentialReply reply;
    };

    AutoFillXPCListener* xpcListener = nil;
    // One per request type; a newer request of the same type replaces the older one
    QHash<int, PendingRequest> pendingRequests;
    // Identities last published per entry (keyed by recordIdentifier), so updates
    // and removals know what to remove even after the entry's fields changed
    NSMutableDictionary<NSString*, NSArray*>* publishedIdentitiesByEntry = nil;
};

AutoFillService::AutoFillService()
    : d(new Private)
{
}

AutoFillService::~AutoFillService() = default;

void AutoFillService::start()
{
    if (config()->get(Config::AutoFill_HelperEnabled).toBool()) {
        NSError* agentError = nil;
        if (![autoFillHelperService() registerAndReturnError:&agentError]) {
            NSLog(@"Failed to register agent service: %@", agentError);
        }
    }

    AutoFillXPCListener* service = [[AutoFillXPCListener alloc] init];
    [service start];
    d->xpcListener = service;

    connectSignals();

    connect(qApp, &QApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive) {
            checkCredentialStoreEnabled();
        }
    });
    checkCredentialStoreEnabled();
}

void AutoFillService::checkCredentialStoreEnabled()
{
    [ASCredentialIdentityStore.sharedStore
        getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState* state) {
            const bool enabled = state.isEnabled;
            dispatch_async(dispatch_get_main_queue(), ^{
                const bool wasDisabled = m_storeStateKnown && !m_storeEnabled;
                m_storeStateKnown = true;
                m_storeEnabled = enabled;
                if (enabled && wasDisabled) {
                    clearCredentialStoreAndRepublish();
                }
            });
        }];
}

AutoFillService* AutoFillService::instance()
{
    static AutoFillService* s_instance = new AutoFillService();
    return s_instance;
}

static bool approvalRequired()
{
    return config()->get(Config::AutoFill_AskBeforeFilling).toBool();
}

static void confirmUserPresence(void (^completion)(BOOL confirmed))
{
    if (!approvalRequired()) {
        completion(YES);
        return;
    }

    LAContext* context = [[LAContext alloc] init];
    NSString* reason = QCoreApplication::translate("AutoFill", "fill in a login from your database").toNSString();
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:reason
                      reply:^(BOOL success, NSError*) {
                          dispatch_async(dispatch_get_main_queue(), ^{
                              completion(success);
                          });
                      }];
}

static void logIfFailed(BOOL success, NSError* error, NSString* what)
{
    if (!success) {
        NSLog(@"AutoFill: failed to %@: %@", what, error.localizedDescription);
    }
}

// Runs block on the main thread if KeePassXC is enabled as an AutoFill provider
static void whenCredentialStoreEnabled(void (^block)(void))
{
    [ASCredentialIdentityStore.sharedStore
        getCredentialIdentityStoreStateWithCompletion:^(ASCredentialIdentityStoreState* state) {
            if (state.isEnabled) {
                dispatch_async(dispatch_get_main_queue(), block);
            }
        }];
}

void AutoFillService::fetchCredential(ASCredentialRequestType type,
                                      NSString* recordIdentifier,
                                      bool interactive,
                                      CredentialMaker makeCredential,
                                      CredentialReply reply)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        QUuid dbUuid;
        QUuid entryUuid;
        if (!parseRecordIdentifier(recordIdentifier, dbUuid, entryUuid)) {
            reply(nil, AutoFillError(AutoFillErrorBadIdentifier));
            return;
        }

        DatabaseWidget* targetWidget = findDatabaseWidgetByUuid(dbUuid);
        if (!targetWidget) {
            reply(nil, AutoFillError(AutoFillErrorNotFound));
            return;
        }

        if (targetWidget->isLocked()) {
            if (!interactive) {
                reply(nil, AutoFillError(AutoFillErrorLocked));
                return;
            }
            if (d->pendingRequests.contains(type)) {
                d->pendingRequests.take(type).reply(nil, AutoFillError(AutoFillErrorSuperseded));
            }
            d->pendingRequests.insert(type, {targetWidget, makeCredential, reply});
            watchPendingTarget(targetWidget);
            openDatabase(/*triggerUnlock=*/true, targetWidget);
            return;
        }

        auto database = targetWidget->database();
        if (database.isNull() || !AutoFillDatabaseOptions::isEnabled(database.data())) {
            reply(nil, AutoFillError(AutoFillErrorNotFound));
            return;
        }

        if (approvalRequired() && !interactive) {
            reply(nil, AutoFillError(AutoFillErrorApprovalRequired));
            return;
        }

        confirmUserPresence(^(BOOL confirmed) {
            if (!confirmed) {
                reply(nil, AutoFillError(AutoFillErrorCancelled));
                return;
            }
            id credential = makeCredential(database);
            reply(credential, credential ? nil : AutoFillError(AutoFillErrorNotFound));
        });
    });
}

void AutoFillService::fetchPasswordCredentialFromIdentity(ASPasswordCredentialIdentity* identity,
                                                          bool interactive,
                                                          void (^reply)(ASPasswordCredential* __strong credential,
                                                                        NSError* __strong error))
{
    NSString* recordIdentifier = identity.recordIdentifier;
    fetchCredential(
        ASCredentialRequestTypePassword,
        recordIdentifier,
        interactive,
        ^id(QSharedPointer<Database> db) {
            return getPasswordCredentialFromIdentity(recordIdentifier, db);
        },
        ^(id credential, NSError* error) {
            reply(credential, error);
        });
}

void AutoFillService::fetchOneTimeCodeForIdentity(ASOneTimeCodeCredentialIdentity* identity,
                                                  bool interactive,
                                                  void (^reply)(ASOneTimeCodeCredential* __strong credential,
                                                                NSError* __strong error))
{
    NSString* recordIdentifier = identity.recordIdentifier;
    fetchCredential(
        ASCredentialRequestTypeOneTimeCode,
        recordIdentifier,
        interactive,
        ^id(QSharedPointer<Database> db) {
            return getOneTimeCodeCredentialFromIdentity(recordIdentifier, db);
        },
        ^(id credential, NSError* error) {
            reply(credential, error);
        });
}

void AutoFillService::fetchPasskeyCredentialFromPasskeyRequest(
    ASPasskeyCredentialRequest* request,
    bool interactive,
    void (^reply)(ASPasskeyAssertionCredential* __strong credential, NSError* __strong error))
{
    fetchCredential(
        ASCredentialRequestTypePasskeyAssertion,
        request.credentialIdentity.recordIdentifier,
        interactive,
        ^id(QSharedPointer<Database> db) {
            return getPasskeyCredentialFromPasskeyRequest(request, db);
        },
        ^(id credential, NSError* error) {
            reply(credential, error);
        });
}

bool AutoFillService::openDatabase(bool triggerUnlock, DatabaseWidget* targetWidget)
{
    auto* window = getMainWindow();
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

    if (triggerUnlock) {
        if (!m_bringToFrontRequested) {
            m_bringToFrontRequested = true;
            updateWindowState();
        }
        emit requestUnlock(targetWidget);
    }

    return false;
}

void AutoFillService::updateWindowState()
{
    if (macUtils()->isHidden()) {
        m_prevWindowState = WindowState::Hidden;
    } else if (getMainWindow()->isMinimized()) {
        m_prevWindowState = WindowState::Minimized;
    } else {
        m_prevWindowState = WindowState::Normal;
    }
}

void AutoFillService::hideWindow() const
{
    if (m_prevWindowState == WindowState::Minimized) {
        getMainWindow()->showMinimized();
    } else if (m_prevWindowState == WindowState::Hidden) {
        macUtils()->hideOwnWindow();
    } else {
        macUtils()->raiseLastActiveWindow();
    }
}

void AutoFillService::activeDatabaseChanged(DatabaseWidget* dbWidget)
{
    m_currentDatabaseWidget = dbWidget;
}

// Unlocked database with this public UUID that is offered to AutoFill, or null
static QSharedPointer<Database> unlockedAutoFillDatabase(DatabaseWidget* widget)
{
    if (!widget || widget->isLocked()) {
        return {};
    }
    auto database = widget->database();
    if (database.isNull() || !database->isInitialized() || !AutoFillDatabaseOptions::isEnabled(database.data())) {
        return {};
    }
    return database;
}

void AutoFillService::fetchExistingPasskeysForRegistrationRequest(
    ASPasskeyCredentialRequest* request,
    NSString* databaseUuid,
    void (^reply)(NSArray<NSArray<NSString*>*>* __strong entries, NSError* __strong error))
{
    dispatch_async(dispatch_get_main_queue(), ^{
        auto database =
            unlockedAutoFillDatabase(findDatabaseWidgetByUuid(Tools::hexToUuid(QString::fromNSString(databaseUuid))));
        if (database.isNull()) {
            reply(nil, AutoFillError(AutoFillErrorNotFound));
            return;
        }

        auto* identity = static_cast<ASPasskeyCredentialIdentity*>(request.credentialIdentity);
        NSMutableArray<NSArray<NSString*>*>* entries = [NSMutableArray array];
        for (Entry* entry : searchEntries(database,
                                          QString::fromNSString(identity.relyingPartyIdentifier),
                                          /*passkeyOnly=*/true,
                                          /*totpOnly=*/false)) {
            [entries addObject:@[
                Tools::uuidToHex(entry->uuid()).toNSString(),
                entry->resolveMultiplePlaceholders(entry->title()).toNSString(),
                entry->resolveMultiplePlaceholders(entry->username()).toNSString()
            ]];
        }
        reply(entries, nil);
    });
}

void AutoFillService::registerPasskeyForRequest(ASPasskeyCredentialRequest* request,
                                                NSString* databaseUuid,
                                                NSString* existingEntryUuid,
                                                void (^reply)(ASPasskeyRegistrationCredential* __strong credential,
                                                              NSError* __strong error))
{
    dispatch_async(dispatch_get_main_queue(), ^{
        auto* widget = findDatabaseWidgetByUuid(Tools::hexToUuid(QString::fromNSString(databaseUuid)));
        auto database = unlockedAutoFillDatabase(widget);
        if (database.isNull()) {
            reply(nil, AutoFillError(AutoFillErrorNotFound));
            return;
        }

        Entry* existingEntry = nullptr;
        if (existingEntryUuid.length > 0) {
            existingEntry =
                database->rootGroup()->findEntryByUuid(Tools::hexToUuid(QString::fromNSString(existingEntryUuid)));
            if (!existingEntry) {
                reply(nil, AutoFillError(AutoFillErrorNotFound));
                return;
            }
        }

        // Saved through the widget (atomic save, backups) instead of the extension's direct write
        Entry* registeredEntry = nullptr;
        ASPasskeyRegistrationCredential* credential = createPasskeyRegistrationCredential(
            request, database, existingEntry, /*saveDatabase=*/false, &registeredEntry);
        if (!credential || !widget->save()) {
            reply(nil, AutoFillError(AutoFillErrorSaveFailed));
            return;
        }
        // Passkey attributes don't emit entryDataChanged, so the entry hooks miss them
        publishEntryIdentities(registeredEntry, database->publicUuid());
        reply(credential, nil);
    });
}

void AutoFillService::connectSignals()
{
    if (m_signalsConnected) {
        return;
    }

    if (auto* window = getMainWindow()) {
        connect(window, &MainWindow::databaseUnlocked, this, [this](DatabaseWidget* widget) { watchDatabase(widget); });
        connect(window, &MainWindow::databaseLocked, this, [this](DatabaseWidget* widget) { unwatchDatabase(widget); });
    }

    connect(getMainWindow(), &MainWindow::activeDatabaseChanged, this, &AutoFillService::activeDatabaseChanged);
    connect(getMainWindow(), &MainWindow::databaseUnlocked, this, &AutoFillService::databaseUnlocked);
    connect(getMainWindow(),
            &MainWindow::databaseUnlockDialogFinished,
            this,
            &AutoFillService::databaseUnlockDialogFinished);

    m_signalsConnected = true;
}

DatabaseWidget* AutoFillService::findDatabaseWidgetByUuid(const QUuid& dbUuid) const
{
    if (auto* window = getMainWindow()) {
        for (auto* widget : window->getOpenDatabases()) {
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

void AutoFillService::watchDatabase(DatabaseWidget* widget)
{
    if (!widget || m_watchedDatabases.contains(widget)) {
        return;
    }

    m_watchedDatabases.insert(widget);
    // Drop connections left over from a previous lock/unlock cycle
    disconnect(widget, nullptr, this, nullptr);

    // The database object is swapped on unlock or Save As: republish and re-hook like a
    // fresh unlock; the old tree's connections go away with its Group/Entry objects
    connect(widget,
            &DatabaseWidget::databaseReplaced,
            this,
            [this, widget](const QSharedPointer<Database>& oldDb, const QSharedPointer<Database>&) {
                // Old tree is released right after this; its entry teardown
                // must not look like deletions and wipe the published identities
                unhookDatabase(oldDb);
                saveCredentialStore(widget);
                hookDatabaseGroups(widget);
            });
    connect(widget, &DatabaseWidget::databaseLocked, this, [this, widget]() { unwatchDatabase(widget); });

    saveCredentialStore(widget);
    hookDatabaseGroups(widget);
}

// Undoes watchDatabase on lock, so the next unlock publishes and hooks only once
void AutoFillService::unwatchDatabase(DatabaseWidget* widget)
{
    if (!widget || !m_watchedDatabases.remove(widget)) {
        return;
    }
    disconnect(widget, nullptr, this, nullptr);
    unhookDatabase(widget->database());
}

void AutoFillService::hookDatabaseGroups(DatabaseWidget* widget)
{
    if (!widget) {
        return;
    }
    auto db = widget->database();
    if (db.isNull()) {
        return;
    }

    QUuid publicUuid = db->publicUuid();

    for (Group* group : db->rootGroup()->groupsRecursive(/*includeSelf=*/true)) {
        hookGroup(group, publicUuid);
    }

    // Fires for new groups anywhere in the tree, so their future entries are
    // tracked too without re-walking the tree
    connect(db.data(), &Database::groupAboutToAdd, this, [this, publicUuid](Group* group, int) {
        hookGroup(group, publicUuid);
    });

    if (db->isInitialized()) {
        QPointer<Database> dbPtr(db.data());
        connect(
            db.data(), &Database::filePathChanged, this, [publicUuid, dbPtr](const QString&, const QString& newPath) {
                if (dbPtr && AutoFillDatabaseOptions::isEnabled(dbPtr) && !newPath.isEmpty()) {
                    config()->setDatabaseFilePath(Tools::uuidToHex(publicUuid), newPath);
                    const auto keyFile = config()->get(Config::LastKeyFiles).toHash().value(newPath).toString();
                    AutoFillBookmarks::save(Tools::uuidToHex(publicUuid), newPath, keyFile);
                }
            });

        // Re-publish (or withdraw) everything when "Use this database for AutoFill" changes
        QPointer<DatabaseWidget> widgetPtr(widget);
        auto lastEnabled = std::make_shared<bool>(AutoFillDatabaseOptions::isEnabled(db.data()));
        connect(db->metadata()->customData(), &CustomData::modified, this, [this, widgetPtr, dbPtr, lastEnabled]() {
            if (!widgetPtr || !dbPtr) {
                return;
            }
            const bool enabled = AutoFillDatabaseOptions::isEnabled(dbPtr);
            if (enabled != *lastEnabled) {
                *lastEnabled = enabled;
                saveCredentialStore(widgetPtr);
            }
        });
    }
}

void AutoFillService::hookGroup(Group* group, const QUuid& dbUuid)
{
    if (!group || m_hookedGroups.contains(group)) {
        return;
    }
    m_hookedGroups.insert(group);

    connect(group, &Group::entryAdded, this, [this, dbUuid](Entry* entry) { onEntryAdded(entry, dbUuid); });
    connect(group, &Group::entryRemoved, this, [this, dbUuid](Entry* entry) { onEntryRemoved(entry, dbUuid); });
    connect(group, &Group::entryDataChanged, this, [this, dbUuid](Entry* entry) { onEntryDataChanged(entry, dbUuid); });
    connect(group, &QObject::destroyed, this, [this, group]() { m_hookedGroups.remove(group); });
}

// Wipe the store, then publish every database that is unlocked right now;
// locked databases come back when they are next unlocked
void AutoFillService::clearCredentialStoreAndRepublish()
{
    // Recorded up front so the republish below doesn't trigger another clear
    config()->set(Config::AutoFill_LastFullClear, QDateTime::currentDateTimeUtc());

    whenCredentialStoreEnabled(^{
        [ASCredentialIdentityStore.sharedStore
            removeAllCredentialIdentitiesWithCompletion:^(BOOL success, NSError* error) {
                logIfFailed(success, error, @"clear credential identities");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [d->publishedIdentitiesByEntry removeAllObjects];
                    if (auto* window = getMainWindow()) {
                        for (auto* widget : window->getOpenDatabases()) {
                            if (widget && m_watchedDatabases.contains(widget) && !widget->isLocked()) {
                                saveCredentialStore(widget);
                            }
                        }
                    }
                });
            }];
    });
}

void AutoFillService::unhookDatabase(const QSharedPointer<Database>& db)
{
    if (db.isNull()) {
        return;
    }
    disconnect(db.data(), nullptr, this, nullptr);
    disconnect(db->metadata()->customData(), nullptr, this, nullptr);
    if (!db->rootGroup()) {
        return;
    }
    for (Group* group : db->rootGroup()->groupsRecursive(/*includeSelf=*/true)) {
        disconnect(group, nullptr, this, nullptr);
        m_hookedGroups.remove(group);
    }
}

// Publishes every entry of a just unlocked or replaced database; can run again for the
// same database, so publishEntryIdentities replaces per entry instead of duplicating
void AutoFillService::saveCredentialStore(DatabaseWidget* widget)
{
    if (!widget) {
        return;
    }

    auto db = widget->database();
    if (db.isNull()) {
        return;
    }

    // Locked placeholder (headers only): keep what was published at unlock
    if (!db->isInitialized()) {
        return;
    }

    QUuid publicUuid = db->publicUuid();
    const bool enabled = AutoFillDatabaseOptions::isEnabled(db.data());

    // Lets the extension find the file for this database's record identifiers;
    // a database excluded from AutoFill is not offered there at all
    if (enabled && !db->filePath().isEmpty()) {
        config()->setDatabaseFilePath(Tools::uuidToHex(publicUuid), db->filePath());
        // Grant the sandboxed extension access to the file (and remembered key file)
        const auto keyFile = config()->get(Config::LastKeyFiles).toHash().value(db->filePath()).toString();
        AutoFillBookmarks::save(Tools::uuidToHex(publicUuid), db->filePath(), keyFile);
    } else if (!enabled) {
        config()->removeDatabaseFilePath(Tools::uuidToHex(publicUuid));
        AutoFillBookmarks::remove(Tools::uuidToHex(publicUuid));
    }

    if (!d->publishedIdentitiesByEntry) {
        d->publishedIdentitiesByEntry = [NSMutableDictionary dictionary];
    }

    // Only AutoFill database: make the store match it exactly, which also drops
    // leftovers from earlier sessions and deleted entries
    if (enabled && config()->getAllDatabaseFilePaths().size() <= 1) {
        NSMutableDictionary<NSString*, NSArray*>* byEntry = [NSMutableDictionary dictionary];
        NSMutableArray* allIdentities = [NSMutableArray array];
        for (Entry* entry : db->rootGroup()->entriesRecursive()) {
            if (entry->isRecycled()) {
                continue;
            }
            NSArray* identities = identitiesForEntry(entry, publicUuid);
            if (identities.count > 0) {
                byEntry[recordIdentifierForEntry(entry, publicUuid)] = identities;
                [allIdentities addObjectsFromArray:identities];
            }
        }
        d->publishedIdentitiesByEntry = byEntry;
        whenCredentialStoreEnabled(^{
            [ASCredentialIdentityStore.sharedStore
                replaceCredentialIdentityEntries:allIdentities
                                      completion:^(BOOL success, NSError* error) {
                                          logIfFailed(success, error, @"replace credential identities");
                                      }];
        });
        return;
    }

    // Several AutoFill databases: identities of other (possibly locked) databases
    // must stay, so leftovers are only dropped by a full clear once a week
    const auto lastFullClear = config()->get(Config::AutoFill_LastFullClear).toDateTime();
    if (!lastFullClear.isValid() || lastFullClear.daysTo(QDateTime::currentDateTimeUtc()) >= 7) {
        clearCredentialStoreAndRepublish();
        return;
    }

    NSMutableSet<NSString*>* currentKeys = [NSMutableSet set];
    if (enabled) {
        for (Entry* entry : db->rootGroup()->entriesRecursive()) {
            if (entry->isRecycled()) {
                continue;
            }
            publishEntryIdentities(entry, publicUuid);
            [currentKeys addObject:recordIdentifierForEntry(entry, publicUuid)];
        }
    }

    // Remove this database's identities whose entries are gone (e.g. deleted while locked),
    // or all of them if it's excluded from AutoFill; other databases are untouched
    NSString* dbPrefix = [NSString stringWithFormat:@"%@:", Tools::uuidToHex(publicUuid).toNSString()];
    NSMutableArray* staleIdentities = [NSMutableArray array];
    for (NSString* key in d->publishedIdentitiesByEntry.allKeys) {
        if ([key hasPrefix:dbPrefix] && ![currentKeys containsObject:key]) {
            [staleIdentities addObjectsFromArray:d->publishedIdentitiesByEntry[key]];
            [d->publishedIdentitiesByEntry removeObjectForKey:key];
        }
    }
    if (staleIdentities.count > 0) {
        [ASCredentialIdentityStore.sharedStore
            removeCredentialIdentityEntries:staleIdentities
                                 completion:^(BOOL success, NSError* error) {
                                     logIfFailed(success, error, @"remove stale credential identities");
                                 }];
    }
}

// Password, one-time code and passkey identities an entry should have in the store
NSArray* AutoFillService::identitiesForEntry(Entry* entry, const QUuid& dbUuid)
{
    DatabaseWidget* widget = findDatabaseWidgetByUuid(dbUuid);
    QString dbName = widget ? widget->displayName() : QString();

    NSMutableArray* identities = [NSMutableArray array];
    if (auto* password = getPasswordCredentialIdentityFromEntry(entry, dbUuid, dbName)) {
        [identities addObject:password];
    }
    if (auto* oneTimeCode = getOneTimeCodeCredentialIdentityFromEntry(entry, dbUuid)) {
        [identities addObject:oneTimeCode];
    }
    if (auto* passkey = getPasskeyCredentialIdentityFromEntry(entry, dbUuid)) {
        [identities addObject:passkey];
    }
    return identities;
}

// Removes what the entry last published before saving its new identities: the store only replaces
// in place with incremental updates, otherwise Safari shows duplicate suggestions
void AutoFillService::publishEntryIdentities(Entry* entry, const QUuid& dbUuid)
{
    if (!entry || !AutoFillDatabaseOptions::isEnabled(entry->database())) {
        return;
    }

    if (!d->publishedIdentitiesByEntry) {
        d->publishedIdentitiesByEntry = [NSMutableDictionary dictionary];
    }

    NSString* entryKey = recordIdentifierForEntry(entry, dbUuid);
    NSArray* previousIdentities = d->publishedIdentitiesByEntry[entryKey];
    NSArray* freshIdentities = identitiesForEntry(entry, dbUuid);

    if (previousIdentities.count > 0) {
        [ASCredentialIdentityStore.sharedStore
            removeCredentialIdentityEntries:previousIdentities
                                 completion:^(BOOL success, NSError* error) {
                                     logIfFailed(success, error, @"remove outdated credential identities");
                                 }];
    }

    if (freshIdentities.count > 0) {
        [ASCredentialIdentityStore.sharedStore
            saveCredentialIdentityEntries:freshIdentities
                               completion:^(BOOL success, NSError* error) {
                                   logIfFailed(success, error, @"save credential identities");
                               }];
        d->publishedIdentitiesByEntry[entryKey] = freshIdentities;
    } else {
        [d->publishedIdentitiesByEntry removeObjectForKey:entryKey];
    }
}

void AutoFillService::onEntryAdded(Entry* entry, const QUuid& dbUuid)
{
    if (!entry || entry->isRecycled()) {
        return;
    }
    publishEntryIdentities(entry, dbUuid);
}

void AutoFillService::onEntryDataChanged(Entry* entry, const QUuid& dbUuid)
{
    if (!entry) {
        return;
    }
    if (entry->isRecycled()) {
        onEntryRemoved(entry, dbUuid);
        return;
    }
    publishEntryIdentities(entry, dbUuid);
}

void AutoFillService::onEntryRemoved(Entry* entry, const QUuid& dbUuid)
{
    if (!entry || !d->publishedIdentitiesByEntry) {
        return;
    }

    NSString* entryKey = recordIdentifierForEntry(entry, dbUuid);
    NSArray* previousIdentities = d->publishedIdentitiesByEntry[entryKey];
    if (previousIdentities.count == 0) {
        return;
    }

    [ASCredentialIdentityStore.sharedStore
        removeCredentialIdentityEntries:previousIdentities
                             completion:^(BOOL success, NSError* error) {
                                 logIfFailed(success, error, @"remove credential identities");
                             }];

    [d->publishedIdentitiesByEntry removeObjectForKey:entryKey];
}

void AutoFillService::databaseUnlocked(DatabaseWidget* dbWidget)
{
    if (dbWidget) {
        finishPendingRequests(dbWidget, nil);
    }
}

void AutoFillService::databaseUnlockDialogFinished(bool accepted, DatabaseWidget* dbWidget)
{
    // When accepted, databaseUnlocked() answers once the widget finishes unlocking
    if (!accepted) {
        finishPendingRequests(dbWidget, AutoFillError(AutoFillErrorCancelled));
    }
}

// Answers a queued request once its locked tab is closed instead of unlocked
void AutoFillService::watchPendingTarget(DatabaseWidget* widget)
{
    connect(widget,
            &QObject::destroyed,
            this,
            &AutoFillService::cancelOrphanedRequests,
            static_cast<Qt::ConnectionType>(Qt::QueuedConnection | Qt::UniqueConnection));
}

void AutoFillService::cancelOrphanedRequests()
{
    finishPendingRequests(nullptr, AutoFillError(AutoFillErrorCancelled));
}

void AutoFillService::finishPendingRequests(DatabaseWidget* dbWidget, NSError* error)
{
    QList<Private::PendingRequest> finished;
    for (auto it = d->pendingRequests.begin(); it != d->pendingRequests.end();) {
        if (it->target == dbWidget) {
            finished.append(*it);
            it = d->pendingRequests.erase(it);
        } else {
            ++it;
        }
    }

    for (const auto& request : finished) {
        if (error) {
            request.reply(nil, error);
            continue;
        }
        auto database = dbWidget->database();
        id credential = !database.isNull() && AutoFillDatabaseOptions::isEnabled(database.data())
                            ? request.makeCredential(database)
                            : nil;
        request.reply(credential, credential ? nil : AutoFillError(AutoFillErrorNotFound));
    }

    // Another database may have unlocked (e.g. the user opened another tab); keep
    // waiting, with the app in front, until the target database unlocks
    if (!finished.isEmpty() && m_bringToFrontRequested) {
        m_bringToFrontRequested = false;
        hideWindow();
    }
}
