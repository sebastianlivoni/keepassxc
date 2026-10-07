#ifndef KEEPASSXC_AUTOFILLCREDENTIALS_H
#define KEEPASSXC_AUTOFILLCREDENTIALS_H

#include "core/Database.h"
#include "core/Group.h"

#ifdef __OBJC__
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
class ASPasskeyCredentialRequestParameters;
class NSError;
#endif

#include <QSharedPointer>

// Credentials and identities for AutoFill, built from database entries
namespace AutoFillCredentials
{
    // Entry a record identifier refers to, or null
    Entry* entryForRecord(const NSString* recordIdentifier, const QSharedPointer<Database>& db);
    ASPasswordCredential* getPasswordCredentialFromIdentity(const NSString* recordIdentifier,
                                                            const QSharedPointer<Database>& db);
    ASOneTimeCodeCredential* getOneTimeCodeCredentialFromIdentity(const NSString* recordIdentifier,
                                                                  const QSharedPointer<Database>& db);
    ASPasskeyAssertionCredential* getPasskeyCredentialFromPasskeyRequest(const ASPasskeyCredentialRequest* request,
                                                                         const QSharedPointer<Database>& db);

    ASPasswordCredentialIdentity*
    getPasswordCredentialIdentityFromEntry(const Entry* entry, const QUuid dbUuid, const QString dbName);
    ASOneTimeCodeCredentialIdentity* getOneTimeCodeCredentialIdentityFromEntry(const Entry* entry, const QUuid dbUuid);
    ASPasskeyCredentialIdentity* getPasskeyCredentialIdentityFromEntry(const Entry* entry, const QUuid dbUuid);

    ASPasskeyRegistrationCredential* createPasskeyRegistrationCredential(const ASPasskeyCredentialRequest* request,
                                                                         const QSharedPointer<Database>& db,
                                                                         Entry* existingEntry = nullptr,
                                                                         bool saveDatabase = true,
                                                                         Entry** registeredEntry = nullptr);
    NSString* recordIdentifierForEntry(const Entry* entry, const QUuid dbUuid);
    bool parseRecordIdentifier(const NSString* recordIdentifier, QUuid& dbUuid, QUuid& entryUuid);

    QList<Entry*>
    searchEntries(const QSharedPointer<Database>& db, const QString& siteUrl, bool passkeyOnly, bool totpOnly);
    // Entries matching any of the URLs, best match first
    QList<Entry*>
    searchEntries(const QSharedPointer<Database>& db, const QStringList& siteUrls, bool passkeyOnly, bool totpOnly);
    QList<Entry*> allEntries(const QSharedPointer<Database>& db, bool passkeyOnly, bool totpOnly);

    ASPasswordCredential* getPasswordCredentialFromEntry(const Entry* entry);
    ASOneTimeCodeCredential* getOneTimeCodeCredentialFromEntry(const Entry* entry);
    ASPasskeyAssertionCredential*
    getPasskeyCredentialFromEntry(const Entry* entry,
                                  NSData* clientDataHash,
                                  const ASPasskeyCredentialRequestParameters* requestParameters);
} // namespace AutoFillCredentials

#endif // KEEPASSXC_AUTOFILLCREDENTIALS_H
