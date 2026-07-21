#ifndef KEEPASSX_AUTOFILLSERVICEV2_H
#define KEEPASSX_AUTOFILLSERVICEV2_H

#include "AutoFillService.h"

class DatabaseWidget;
class Group;

class AutoFillServiceV2 : public QObject, public AutoFillService {
  Q_OBJECT

public:
  static AutoFillServiceV2 *instance();
  ~AutoFillServiceV2();

  void start();
  void fetchPasswordCredentialFromIdentity(
      ASPasswordCredentialIdentity *identity,
      void (^reply)(ASPasswordCredential *__strong credential,
                    NSError *__strong error));
  void fetchOneTimeCodeForIdentity(
      ASOneTimeCodeCredentialIdentity *identity,
      void (^reply)(ASOneTimeCodeCredential *__strong credential,
                    NSError *__strong error));
  void fetchPasskeyCredentialFromPasskeyRequest(
      ASPasskeyCredentialRequest *request,
      void (^reply)(ASPasskeyAssertionCredential *__strong credential,
                    NSError *__strong error));
  void createPasskeyRegistrationCredentialRequest(
      ASPasskeyCredentialRequest *request,
      void (^reply)(ASPasskeyRegistrationCredential *__strong credential,
                    NSError *__strong error));

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
  __strong AutoFillXPCService *m_xpcService;
  __strong ASPasskeyCredentialRequest *m_pendingRequest;
  void (^m_pendingReplyBlock)(ASPasskeyAssertionCredential *__strong,
                              NSError *__strong);

  ASPasswordCredentialIdentity *m_pendingPasswordIdentity = nil;
  void (^m_pendingPasswordReplyBlock)(ASPasswordCredential *__strong,
                                      NSError *__strong) = nil;

  ASOneTimeCodeCredentialIdentity *m_pendingOtpIdentity = nil;
  void (^m_pendingOtpReplyBlock)(ASOneTimeCodeCredential *__strong,
                                 NSError *__strong) = nil;

  // Last-published identities per entry (keyed by its recordIdentifier),
  // so a later per-entry update/removal knows exactly what to remove
  // without needing to reconstruct it from (possibly already-cleared)
  // current entry fields.
  NSMutableDictionary<NSString *, NSArray *> *m_publishedIdentitiesByEntry =
      nil;
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
  void hideWindow() const;

  void saveCredentialStore(DatabaseWidget *widget);
  void resetCredentialStore();

  void connectSignals();
  void watchDatabase(DatabaseWidget *widget);
  void hookDatabaseGroups(DatabaseWidget *widget);
  void hookGroup(Group *group, const QUuid &dbUuid);
  void publishEntryIdentities(Entry *entry, const QUuid &dbUuid);
  void onEntryAdded(Entry *entry, const QUuid &dbUuid);
  void onEntryDataChanged(Entry *entry, const QUuid &dbUuid);
  void onEntryRemoved(Entry *entry, const QUuid &dbUuid);
  DatabaseWidget *findDatabaseWidgetByUuid(const QUuid &dbUuid) const;

  bool m_available{false};
  bool m_running{false};
  bool m_signalsConnected{false};
};

static inline AutoFillServiceV2 *autoFillServiceV2() {
  return AutoFillServiceV2::instance();
}

#endif // KEEPASSX_AUTOFILLSERVICEV2_H
