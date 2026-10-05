#ifndef KEEPASSXC_AUTOFILLSERVICE_H
#define KEEPASSXC_AUTOFILLSERVICE_H

#include "common/AutoFillCredentials.h"

#ifdef __OBJC__
#include "app/AutoFillXPCListener.h"
#endif

class DatabaseWidget;
class Group;

class AutoFillService : public QObject, public AutoFillCredentials {
  Q_OBJECT

public:
  static AutoFillService *instance();
  ~AutoFillService();

  void start();
  // Republishes the store when KeePassXC was just enabled as AutoFill provider
  void checkCredentialStoreEnabled();
  void fetchPasswordCredentialFromIdentity(
      ASPasswordCredentialIdentity *identity, bool interactive,
      void (^reply)(ASPasswordCredential *__strong credential,
                    NSError *__strong error));
  void fetchOneTimeCodeForIdentity(
      ASOneTimeCodeCredentialIdentity *identity, bool interactive,
      void (^reply)(ASOneTimeCodeCredential *__strong credential,
                    NSError *__strong error));
  void fetchPasskeyCredentialFromPasskeyRequest(
      ASPasskeyCredentialRequest *request, bool interactive,
      void (^reply)(ASPasskeyAssertionCredential *__strong credential,
                    NSError *__strong error));

#ifdef __OBJC__
  // ObjC only: the generic NSArray can't be forward declared for C++ (moc)
  void fetchExistingPasskeysForRegistrationRequest(
      ASPasskeyCredentialRequest *request, NSString *databaseUuid,
      void (^reply)(NSArray<NSArray<NSString *> *> *__strong entries,
                    NSError *__strong error));
  void registerPasskeyForRequest(
      ASPasskeyCredentialRequest *request, NSString *databaseUuid,
      NSString *existingEntryUuid,
      void (^reply)(ASPasskeyRegistrationCredential *__strong credential,
                    NSError *__strong error));
#endif

  bool openDatabase(bool triggerUnlock, DatabaseWidget *targetWidget);

signals:
  void requestUnlock(DatabaseWidget *targetWidget);

public slots:
  void databaseUnlocked(DatabaseWidget *dbWidget);
  void activeDatabaseChanged(DatabaseWidget *dbWidget);
  void databaseUnlockDialogFinished(bool accepted, DatabaseWidget *dbWidget);

private:
  enum WindowState { Normal, Minimized, Hidden };

#ifdef __OBJC__
  __strong AutoFillXPCListener *m_xpcListener;
  __strong ASPasskeyCredentialRequest *m_pendingRequest;
  void (^m_pendingReplyBlock)(ASPasskeyAssertionCredential *__strong,
                              NSError *__strong);

  ASPasswordCredentialIdentity *m_pendingPasswordIdentity = nil;
  void (^m_pendingPasswordReplyBlock)(ASPasswordCredential *__strong,
                                      NSError *__strong) = nil;

  ASOneTimeCodeCredentialIdentity *m_pendingOtpIdentity = nil;
  void (^m_pendingOtpReplyBlock)(ASOneTimeCodeCredential *__strong,
                                 NSError *__strong) = nil;

  // Identities last published per entry (keyed by recordIdentifier), so updates
  // and removals know what to remove even after the entry's fields changed
  NSMutableDictionary<NSString *, NSArray *> *m_publishedIdentitiesByEntry =
      nil;

  NSArray *identitiesForEntry(Entry *entry, const QUuid &dbUuid);
#endif

  QPointer<DatabaseWidget> m_pendingPasskeyTargetWidget;
  QPointer<DatabaseWidget> m_pendingPasswordTargetWidget;
  QPointer<DatabaseWidget> m_pendingOtpTargetWidget;

  bool m_bringToFrontRequested;
  WindowState m_prevWindowState;

  QSet<DatabaseWidget *> m_watchedDatabases;
  QSet<Group *> m_hookedGroups;
  QPointer<DatabaseWidget> m_currentDatabaseWidget;

  void updateWindowState();
  void watchPendingTarget(DatabaseWidget *widget);
  void cancelOrphanedRequests();
  void hideWindow() const;

  void saveCredentialStore(DatabaseWidget *widget);
  void clearCredentialStoreAndRepublish();

  void connectSignals();
  void watchDatabase(DatabaseWidget *widget);
  void unwatchDatabase(DatabaseWidget *widget);
  void hookDatabaseGroups(DatabaseWidget *widget);
  void hookGroup(Group *group, const QUuid &dbUuid);
  void unhookDatabase(const QSharedPointer<Database> &db);
  void publishEntryIdentities(Entry *entry, const QUuid &dbUuid);
  void onEntryAdded(Entry *entry, const QUuid &dbUuid);
  void onEntryDataChanged(Entry *entry, const QUuid &dbUuid);
  void onEntryRemoved(Entry *entry, const QUuid &dbUuid);
  DatabaseWidget *findDatabaseWidgetByUuid(const QUuid &dbUuid) const;

  bool m_available{false};
  bool m_running{false};
  bool m_signalsConnected{false};
  bool m_storeStateKnown{false};
  bool m_storeEnabled{false};
};

static inline AutoFillService *autoFillService() {
  return AutoFillService::instance();
}

#endif // KEEPASSXC_AUTOFILLSERVICE_H
