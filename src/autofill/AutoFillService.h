#include "core/Database.h"
#include "core/Group.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <Foundation/Foundation.h>

#include <QSharedPointer>

class AutoFillService {
public:
  ~AutoFillService() = default;
  static AutoFillService *instance();

  void saveCredentialStore(const QSharedPointer<Database> &db);
  void replaceCredentialStore(const QSharedPointer<Database> &db);
  void resetCredentialStore();

  ASPasswordCredential *getPasswordCredentialFromIdentity(
      const ASPasswordCredentialIdentity *identity);
  ASOneTimeCodeCredential *getOneTimeCodeCredentialFromIdentity(
      const ASOneTimeCodeCredentialIdentity *identity);
  ASPasskeyAssertionCredential* getPasskeyCredentialFromPasskeyRequest(const ASPasskeyCredentialRequest *request);

private:
  ASPasswordCredentialIdentity* getPasswordCredentialIdentityFromEntry(const Entry *entry);
  ASOneTimeCodeCredentialIdentity* getOneTimeCodeCredentialIdentityFromEntry(const Entry *entry);
  ASPasskeyCredentialIdentity* getPasskeyCredentialIdentityFromEntry(const Entry *entry);

  ASCredentialServiceIdentifier* getCredentialServiceIdentifierFromEntry(const Entry *entry);

  NSString *uuidStringFromEntry(const Entry *entry);
};

static inline AutoFillService *autoFillService() {
  return AutoFillService::instance();
}
