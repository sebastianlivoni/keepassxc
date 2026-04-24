#ifndef KEEPASSX_AUTOFILLSERVICEV2_H
#define KEEPASSX_AUTOFILLSERVICEV2_H

#include "AutoFillService.h"

class DatabaseWidget;

class AutoFillServiceV2 : public QObject, public AutoFillService {
    Q_OBJECT

public:
  static AutoFillServiceV2 *instance();

  void start();
  void fetchPasswordCredentialFromIdentity(
      ASPasswordCredentialIdentity *identity,
      void (^reply)(ASPasswordCredential *__strong credential,
                    NSError *__strong error));
  void fetchOneTimeCodeForIdentity(
      ASOneTimeCodeCredentialIdentity *identity,
      void (^reply)(ASOneTimeCodeCredential *__strong credential, NSError *__strong error));
  void fetchPasskeyCredentialFromPasskeyRequest(
      ASPasskeyCredentialRequest *request,
      void (^reply)(ASPasskeyAssertionCredential *__strong credential,
                    NSError *__strong error));
  void createPasskeyRegistrationCredentialRequest(
      ASPasskeyCredentialRequest *request,
      void (^reply)(ASPasskeyRegistrationCredential *__strong credential,
                    NSError *__strong error));

private:
#ifdef __OBJC__
  __strong AutoFillXPCService *m_xpcService;
#endif

    QSet<DatabaseWidget*> m_watchedDatabases;

    void saveCredentialStore(const QSharedPointer<Database> &db);
    void replaceCredentialStore();
    void resetCredentialStore();

    void connectSignals();
    void watchDatabase(DatabaseWidget* widget);
    void refreshIdentityStore();

    bool m_available{false};
    bool m_running{false};
    bool m_signalsConnected{false};
};

static inline AutoFillServiceV2 *autoFillServiceV2() {
  return AutoFillServiceV2::instance();
}

#endif // KEEPASSX_AUTOFILLSERVICEV2_H
