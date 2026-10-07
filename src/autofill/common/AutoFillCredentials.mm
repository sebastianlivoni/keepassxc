#include "common/AutoFillCredentials.h"

#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <QApplication>

#include "browser/BrowserMessageBuilder.h"
#include "browser/BrowserPasskeys.h"
#include "browser/BrowserPasskeysClient.h"
#include "browser/BrowserService.h"
#include "core/Entry.h"
#include "core/Global.h"
#include "core/Group.h"
#include "core/Tools.h"
#include "quickunlock/QuickUnlockInterface.h"

#include <AuthenticationServices/AuthenticationServices.h>

#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QUrl>
#include <algorithm>

// Stored BE/BS flag of a passkey, read like BrowserService does for assertions
static bool passkeyFlag(const Entry* entry, const QString& key, bool defaultValue)
{
    if (!entry->attributes()->hasKey(key)) {
        return defaultValue;
    }
    const auto value = entry->attributes()->value(key);
    return value == "1" || value == TRUE_STR;
}

static ASCredentialServiceIdentifier* getCredentialServiceIdentifierFromEntry(const Entry* entry);
static int matchScore(const Entry* entry, const QStringList& siteUrls);

Entry* AutoFillCredentials::entryForRecord(const NSString* recordIdentifier, const QSharedPointer<Database>& db)
{
    QUuid dbUuid;
    QUuid entryUuid;
    if (!db || !db->rootGroup() || !parseRecordIdentifier(recordIdentifier, dbUuid, entryUuid)) {
        return nullptr;
    }
    return db->rootGroup()->findEntryByUuid(entryUuid);
}

ASPasswordCredential* AutoFillCredentials::getPasswordCredentialFromIdentity(const NSString* recordIdentifier,
                                                                             const QSharedPointer<Database>& db)
{
    const Entry* entry = entryForRecord(recordIdentifier, db);
    return entry ? getPasswordCredentialFromEntry(entry) : nil;
}

ASPasswordCredentialIdentity* AutoFillCredentials::getPasswordCredentialIdentityFromEntry(const Entry* entry,
                                                                                          const QUuid dbUuid,
                                                                                          const QString dbName)
{
    QString username = entry->resolveMultiplePlaceholders(entry->username());
    QString password = entry->resolveMultiplePlaceholders(entry->password());

    if (username.isEmpty() || password.isEmpty()) {
        return nullptr;
    }

    auto* serviceIdentifier = getCredentialServiceIdentifierFromEntry(entry);
    if (!serviceIdentifier) {
        return nullptr;
    }

    QString title = entry->resolveMultiplePlaceholders(entry->title());
    if (title.isEmpty()) {
        return nullptr;
    }

    NSString* userString = (title + " (" + dbName + ")").toNSString();

    NSString* recordIdentifier = recordIdentifierForEntry(entry, dbUuid);

    ASPasswordCredentialIdentity* identity =
        [[ASPasswordCredentialIdentity alloc] initWithServiceIdentifier:serviceIdentifier
                                                                   user:userString
                                                       recordIdentifier:recordIdentifier];

    return identity;
}

ASOneTimeCodeCredential* AutoFillCredentials::getOneTimeCodeCredentialFromIdentity(const NSString* recordIdentifier,
                                                                                   const QSharedPointer<Database>& db)
{
    const Entry* entry = entryForRecord(recordIdentifier, db);
    return entry ? getOneTimeCodeCredentialFromEntry(entry) : nil;
}

ASPasskeyRegistrationCredential*
AutoFillCredentials::createPasskeyRegistrationCredential(const ASPasskeyCredentialRequest* request,
                                                         const QSharedPointer<Database>& db,
                                                         Entry* existingEntry,
                                                         bool saveDatabase,
                                                         Entry** registeredEntry)
{
    ASPasskeyCredentialIdentity* identity = static_cast<ASPasskeyCredentialIdentity*>(request.credentialIdentity);

    QByteArray clientDataHash = QByteArray::fromNSData(request.clientDataHash);

    NSNumber* firstAlgorithm = [request.supportedAlgorithms firstObject];
    WebAuthnAlgorithms algorithm = WebAuthnAlgorithms::ES256;

    if (firstAlgorithm != nil) {
        int rawAlg = [firstAlgorithm intValue];
        if (rawAlg == WebAuthnAlgorithms::ES256 || rawAlg == WebAuthnAlgorithms::RS256
            || rawAlg == WebAuthnAlgorithms::EDDSA) {
            algorithm = static_cast<WebAuthnAlgorithms>(rawAlg);
        }
    }

    const auto privateKey = browserPasskeys()->buildCredentialPrivateKey(algorithm);

    QString rpId = QString::fromNSString(identity.relyingPartyIdentifier);
    QString extensions = QString("");
    auto authenticatorData = browserPasskeys()->buildAuthenticatorData(rpId, extensions, true);

    authenticatorData.append(
        browserMessageBuilder()->getArrayFromHexString(QStringLiteral("fdb141b25d84443e8a354698c205a502")));

    const auto credentialId = browserMessageBuilder()->getRandomBytesAsBase64(ID_BYTES);

    const char credentialLength[2] = {0x00, ID_BYTES};
    authenticatorData.append(QByteArray::fromRawData(credentialLength, 2));

    authenticatorData.append(QByteArray::fromBase64(credentialId.toUtf8(), QByteArray::Base64UrlEncoding));

    authenticatorData.append(privateKey.cborEncodedPublicKey);

    // Make AttestationObject; "none" attestation has an empty attStmt by
    // definition (WebAuthn, None Attestation Statement Format)
    QCborMap attStmt;

    QCborMap attestationObject;
    attestationObject.insert(QStringLiteral("fmt"), QStringLiteral("none"));
    attestationObject.insert(QStringLiteral("attStmt"), attStmt);
    attestationObject.insert(QStringLiteral("authData"), authenticatorData);

    QByteArray cborEncoded = QCborValue(attestationObject).toCbor();

    Group* rootGroup = db->rootGroup();
    Entry* entry = existingEntry;
    bool isNewEntry = entry == nullptr;
    if (isNewEntry) {
        entry = new Entry();
        entry->setUuid(QUuid::createUuid());
        entry->setGroup(rootGroup);
        entry->setIcon(13); // KEEPASSXCBROWSER_PASSKEY_ICON
        entry->setTitle(QObject::tr("%1 (Passkey)").arg(QString::fromNSString(identity.relyingPartyIdentifier)));
        entry->setUsername(QString::fromNSString(identity.userName));
        entry->setUrl(QString::fromNSString(identity.relyingPartyIdentifier));
    }

    // Like BrowserService::addPasskeyToEntry, an existing entry keeps its title, username and URL
    entry->beginUpdate();

    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_USERNAME, QString::fromNSString(identity.userName));
    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID, credentialId, true);
    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM, QString(privateKey.privateKeyPem), true);
    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY,
                             QString::fromNSString(identity.relyingPartyIdentifier));
    // Stored base64url encoded, as the readers here and in BrowserService expect
    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_USER_HANDLE,
                             browserMessageBuilder()->getBase64FromArray(QByteArray::fromNSData(identity.userHandle)),
                             true);
    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_FLAG_BE, "1");
    entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_FLAG_BS, "1");
    entry->addTag(QObject::tr("Passkey"));

    entry->endUpdate();

    if (isNewEntry) {
        // Discard the blank pre-creation history snapshot beginUpdate() recorded;
        // an update to an existing entry keeps its real history instead.
        entry->removeHistoryItems(entry->historyItems());
    }

    QString errorMessage;
    // The extension may only access the database file itself (security-scoped
    // bookmark), not its folder, so it can't create a temporary file for an atomic save
    if (saveDatabase && !db->save(Database::DirectWrite, {}, &errorMessage)) {
        return nil;
    }
    if (registeredEntry) {
        *registeredEntry = entry;
    }

    ASPasskeyRegistrationCredential* credential = [ASPasskeyRegistrationCredential
        credentialWithRelyingParty:identity.relyingPartyIdentifier
                    clientDataHash:request.clientDataHash
                      credentialID:QByteArray::fromBase64(credentialId.toUtf8(), QByteArray::Base64UrlEncoding)
                                       .toNSData()
                 attestationObject:cborEncoded.toNSData()];

    return credential;
}

// Credential ID and user handle stored with the entry's passkey
static NSData* passkeyCredentialId(const Entry* entry)
{
    const auto* attributes = entry->attributes();
    const QString credentialId = attributes->hasKey(EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
                                     ? attributes->value(EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
                                     : attributes->value(EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID);
    return browserMessageBuilder()->getArrayFromBase64(credentialId).toNSData();
}

static NSData* passkeyUserHandle(const Entry* entry)
{
    return browserMessageBuilder()
        ->getArrayFromBase64(entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE))
        .toNSData();
}

// Assertion signed with the entry's passkey
static ASPasskeyAssertionCredential* passkeyAssertion(const Entry* entry,
                                                      NSString* relyingParty,
                                                      NSData* clientDataHash,
                                                      NSData* userHandle,
                                                      NSData* credentialID)
{
    if (!entry->hasPasskey()) {
        return nil;
    }

    const auto authenticatorData = browserPasskeys()->buildAuthenticatorData(
        QString::fromNSString(relyingParty),
        QString(),
        false,
        passkeyFlag(entry, EntryAttributes::KPEX_PASSKEY_FLAG_BE, DEFAULT_BE_FLAG),
        passkeyFlag(entry, EntryAttributes::KPEX_PASSKEY_FLAG_BS, DEFAULT_BS_FLAG));
    const auto signature =
        browserPasskeys()->buildSignature(authenticatorData,
                                          QByteArray::fromNSData(clientDataHash),
                                          entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM));

    return [ASPasskeyAssertionCredential credentialWithUserHandle:userHandle
                                                     relyingParty:relyingParty
                                                        signature:signature.toNSData()
                                                   clientDataHash:clientDataHash
                                                authenticatorData:authenticatorData.toNSData()
                                                     credentialID:credentialID];
}

ASPasskeyAssertionCredential*
AutoFillCredentials::getPasskeyCredentialFromPasskeyRequest(const ASPasskeyCredentialRequest* request,
                                                            const QSharedPointer<Database>& db)
{
    auto* identity = static_cast<ASPasskeyCredentialIdentity*>(request.credentialIdentity);
    const Entry* entry = entryForRecord(identity.recordIdentifier, db);
    if (!entry) {
        return nil;
    }
    return passkeyAssertion(
        entry, identity.relyingPartyIdentifier, request.clientDataHash, identity.userHandle, identity.credentialID);
}

ASPasswordCredential* AutoFillCredentials::getPasswordCredentialFromEntry(const Entry* entry)
{
    QString username = entry->resolveMultiplePlaceholders(entry->username());
    QString password = entry->resolveMultiplePlaceholders(entry->password());

    if (username.isEmpty() || password.isEmpty()) {
        return nullptr;
    }

    return [ASPasswordCredential credentialWithUser:username.toNSString() password:password.toNSString()];
}

ASOneTimeCodeCredential* AutoFillCredentials::getOneTimeCodeCredentialFromEntry(const Entry* entry)
{
    QString totp = entry->totp();
    if (totp.isEmpty()) {
        return nullptr;
    }

    return [[ASOneTimeCodeCredential alloc] initWithCode:totp.toNSString()];
}

ASPasskeyAssertionCredential*
AutoFillCredentials::getPasskeyCredentialFromEntry(const Entry* entry,
                                                   NSData* clientDataHash,
                                                   const ASPasskeyCredentialRequestParameters* requestParameters)
{
    return passkeyAssertion(entry,
                            requestParameters.relyingPartyIdentifier,
                            clientDataHash,
                            passkeyUserHandle(entry),
                            passkeyCredentialId(entry));
}

QList<Entry*> AutoFillCredentials::searchEntries(const QSharedPointer<Database>& db,
                                                 const QString& siteUrl,
                                                 bool passkeyOnly,
                                                 bool totpOnly)
{
    return searchEntries(db, QStringList{siteUrl}, passkeyOnly, totpOnly);
}

// Entries outside the recycle bin that aren't hidden from the browser integration
static QList<Entry*> visibleEntries(const QSharedPointer<Database>& db)
{
    QList<Entry*> entries;
    if (!db->rootGroup()) {
        return entries;
    }

    for (const auto& group : db->rootGroup()->groupsRecursive(true)) {
        const auto groupOptionHideEntry = group->resolveCustomDataTriState(BrowserService::OPTION_HIDE_ENTRY);
        if (group->isRecycled() || groupOptionHideEntry == Group::Enable) {
            continue;
        }

        for (auto* entry : group->entries()) {
            if (entry->isRecycled()
                || (groupOptionHideEntry == Group::Inherit
                    && entry->customData()->value(BrowserService::OPTION_HIDE_ENTRY) == TRUE_STR)) {
                continue;
            }
            entries.append(entry);
        }
    }
    return entries;
}

QList<Entry*> AutoFillCredentials::searchEntries(const QSharedPointer<Database>& db,
                                                 const QStringList& siteUrls,
                                                 bool passkeyOnly,
                                                 bool totpOnly)
{
    // Same URL matching as the browser integration
    const auto matchesAnyUrl = [&](Entry* entry) {
        const bool omitWww =
            entry->group()->resolveCustomDataTriState(BrowserService::OPTION_OMIT_WWW) == Group::Enable;
        for (const auto& siteUrl : siteUrls) {
            if (BrowserService::shouldIncludeEntry(entry, siteUrl, siteUrl, omitWww)) {
                return true;
            }
        }
        return false;
    };

    QList<Entry*> entries;
    for (auto* entry : visibleEntries(db)) {
        if (passkeyOnly) {
            if (!entry->hasPasskey()
                || !siteUrls.contains(entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY))) {
                continue;
            }
        } else if ((totpOnly && !entry->hasTotp()) || !matchesAnyUrl(entry)) {
            continue;
        }
        entries.append(entry);
    }

    if (!passkeyOnly) {
        QHash<const Entry*, int> scores;
        for (const auto* entry : entries) {
            scores.insert(entry, matchScore(entry, siteUrls));
        }
        std::stable_sort(entries.begin(), entries.end(), [&](const Entry* a, const Entry* b) {
            return scores.value(a) > scores.value(b);
        });
    }

    return entries;
}

// How closely an entry's URLs match the site: same host and path prefix, same host,
// parent domain, then any other included match (base domain, wildcard)
static int matchScore(const Entry* entry, const QStringList& siteUrls)
{
    int best = 0;
    for (const auto& entryUrl : entry->getAllUrls()) {
        const QUrl url = entryUrl.contains("://") ? QUrl(entryUrl) : QUrl::fromUserInput(entryUrl);
        if (url.host().isEmpty()) {
            continue;
        }
        for (const auto& siteUrl : siteUrls) {
            const QUrl site(siteUrl);
            int score = 1;
            if (url.host().compare(site.host(), Qt::CaseInsensitive) == 0) {
                const auto path = url.path();
                score = (path.length() > 1 && site.path().startsWith(path)) ? 4 : 3;
            } else if (site.host().endsWith("." + url.host(), Qt::CaseInsensitive)) {
                score = 2;
            }
            best = qMax(best, score);
        }
    }
    return best;
}

QList<Entry*> AutoFillCredentials::allEntries(const QSharedPointer<Database>& db, bool passkeyOnly, bool totpOnly)
{
    QList<Entry*> entries = visibleEntries(db);
    entries.erase(std::remove_if(entries.begin(),
                                 entries.end(),
                                 [&](const Entry* entry) {
                                     if (passkeyOnly || totpOnly) {
                                         return (passkeyOnly && !entry->hasPasskey())
                                                || (totpOnly && !entry->hasTotp());
                                     }
                                     return entry->password().isEmpty();
                                 }),
                  entries.end());
    return entries;
}

ASOneTimeCodeCredentialIdentity* AutoFillCredentials::getOneTimeCodeCredentialIdentityFromEntry(const Entry* entry,
                                                                                                const QUuid dbUuid)
{
    if (!entry->hasTotp()) {
        return nullptr;
    }

    auto* serviceIdentifier = getCredentialServiceIdentifierFromEntry(entry);
    if (!serviceIdentifier) {
        return nullptr;
    }

    QString title = entry->resolveMultiplePlaceholders(entry->title());
    if (title.isEmpty()) {
        return nullptr;
    }

    NSString* userString = title.toNSString();

    NSString* recordIdentifier = recordIdentifierForEntry(entry, dbUuid);

    ASOneTimeCodeCredentialIdentity* identity =
        [[ASOneTimeCodeCredentialIdentity alloc] initWithServiceIdentifier:serviceIdentifier
                                                                     label:userString
                                                          recordIdentifier:recordIdentifier];

    return identity;
}

ASPasskeyCredentialIdentity* AutoFillCredentials::getPasskeyCredentialIdentityFromEntry(const Entry* entry,
                                                                                        const QUuid dbUuid)
{
    if (!entry->hasPasskey()) {
        return nullptr;
    }

    NSString* relyingPartyIdentifier =
        entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY).toNSString();
    NSString* userName = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USERNAME).toNSString();

    NSString* recordIdentifier = recordIdentifierForEntry(entry, dbUuid);

    ASPasskeyCredentialIdentity* identity =
        [ASPasskeyCredentialIdentity identityWithRelyingPartyIdentifier:relyingPartyIdentifier
                                                               userName:userName
                                                           credentialID:passkeyCredentialId(entry)
                                                             userHandle:passkeyUserHandle(entry)
                                                       recordIdentifier:recordIdentifier];

    return identity;
}

static ASCredentialServiceIdentifier* getCredentialServiceIdentifierFromEntry(const Entry* entry)
{
    QString webUrl = entry->webUrl();

    if (webUrl.isEmpty()) {
        return nullptr;
    }

    NSString* serviceIdentifierString = webUrl.toNSString();

    ASCredentialServiceIdentifier* serviceIdentifier =
        [[ASCredentialServiceIdentifier alloc] initWithIdentifier:serviceIdentifierString
                                                             type:ASCredentialServiceIdentifierTypeURL];

    return serviceIdentifier;
}

NSString* AutoFillCredentials::recordIdentifierForEntry(const Entry* entry, const QUuid dbUuid)
{
    QString dbUuidHex = Tools::uuidToHex(dbUuid);
    QString entryUuid = entry->uuidToHex();

    return QString("%1:%2").arg(dbUuidHex, entryUuid).toNSString();
}

bool AutoFillCredentials::parseRecordIdentifier(const NSString* recordIdentifier, QUuid& dbUuid, QUuid& entryUuid)
{
    if (!recordIdentifier)
        return false;

    QString composite = QString::fromNSString(recordIdentifier);

    int colonIndex = composite.indexOf(':');
    if (colonIndex == -1)
        return false;

    dbUuid = Tools::hexToUuid(composite.left(colonIndex));
    entryUuid = Tools::hexToUuid(composite.mid(colonIndex + 1));
    return true;
}
