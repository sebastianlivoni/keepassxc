#ifndef KEEPASSX_AUTOFILL_H
#define KEEPASSX_AUTOFILL_H

#include "core/Database.h"
#include "core/Group.h"

#ifdef __OBJC__
#include "AutoFillXPCService.h"
#include <AuthenticationServices/AuthenticationServices.h>
#include <Foundation/Foundation.h>
#else
// Forward declare ObjC types for C++ translation units
class ASPasswordCredential;
class ASPasswordCredentialIdentity;
class ASOneTimeCodeCredential;
class ASOneTimeCodeCredentialIdentity;
class ASPasskeyAssertionCredential;
class ASPasskeyRegistrationCredential;
class ASPasskeyCredentialRequest;
class ASPasskeyCredentialIdentity;
class ASPasswordCredentialRequest;
class ASCredentialServiceIdentifier;
class ASOneTimeCodeCredentialRequest;
class NSError;
#endif

#include <QSharedPointer>

class AutoFillService {

public:
  ~AutoFillService() = default;
  static AutoFillService *instance();

  void updateEntry();

  ASPasswordCredential *
  getPasswordCredentialFromIdentity(const NSString *recordIdentifier,
                                    const QSharedPointer<Database> &db);
  ASPasswordCredential *getPasswordCredentialFromIdentity(
      const ASPasswordCredentialIdentity *identity,
      const QSharedPointer<Database> &db);
  ASOneTimeCodeCredential *
  getOneTimeCodeCredentialFromIdentity(const NSString *recordIdentifier,
                                       const QSharedPointer<Database> &db);

  ASOneTimeCodeCredential *getOneTimeCodeCredentialFromIdentity(
      const ASOneTimeCodeCredentialIdentity *identity,
      const QSharedPointer<Database> &db);
  ASPasskeyAssertionCredential *getPasskeyCredentialFromPasskeyRequest(
      const ASPasskeyCredentialRequest *request,
      const QSharedPointer<Database> &db);
  ASPasswordCredential *getPasswordCredentialFromPasswordRequest(
      const ASPasswordCredentialRequest *request,
      const QSharedPointer<Database> &db);
  ASPasswordCredential *getOneTimeCodeCredentialFromPasswordRequest(
      const ASOneTimeCodeCredentialRequest *request,
      const QSharedPointer<Database> &db);

  ASPasswordCredentialIdentity *
  getPasswordCredentialIdentityFromEntry(const Entry *entry,
                                         const QUuid dbUuid,
                                         const QString dbName);
  ASOneTimeCodeCredentialIdentity *
  getOneTimeCodeCredentialIdentityFromEntry(const Entry *entry,
                                            const QUuid dbUuid);
  ASPasskeyCredentialIdentity *
  getPasskeyCredentialIdentityFromEntry(const Entry *entry, const QUuid dbUuid);

  ASPasskeyRegistrationCredential *
  createPasskeyRegistrationCredential(const ASPasskeyCredentialRequest *request,
                                      const QSharedPointer<Database> &db);
                                      bool parseRecordIdentifier(const NSString *recordIdentifier, QUuid &dbUuid,
                                                                 QUuid &entryUuid);

private:
  ASCredentialServiceIdentifier *
  getCredentialServiceIdentifierFromEntry(const Entry *entry);

  NSString *recordIdentifierForEntry(const Entry *entry, const QUuid dbUuid);
};

static inline AutoFillService *autoFillService() {
  return AutoFillService::instance();
}

#endif // KEEPASSX_AUTOFILL_H
