#include "AutoFillService.h"

#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <QApplication>

#include "browser/BrowserMessageBuilder.h"
#include "browser/BrowserPasskeys.h"
#include "browser/BrowserPasskeysClient.h"
#include "browser/BrowserService.h"
#include "browser/BrowserSettings.h"
#include "core/Entry.h"
#include "core/Global.h"
#include "core/Group.h"
#include "core/Tools.h"
#include "gui/UrlTools.h"
#include "quickunlock/QuickUnlockInterface.h"

#include <AuthenticationServices/AuthenticationServices.h>

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QRegularExpression>
#include <QString>
#include <QUrl>

AutoFillService *AutoFillService::instance() {
  static AutoFillService instance;
  return &instance;
}

ASPasswordCredential *AutoFillService::getPasswordCredentialFromIdentity(
    const ASPasswordCredentialIdentity *identity,
    const QSharedPointer<Database> &db) {
  NSString *recordIdentifier = identity.recordIdentifier;

  return getPasswordCredentialFromIdentity(recordIdentifier, db);
}

ASPasswordCredential *AutoFillService::getPasswordCredentialFromIdentity(
    const NSString *recordIdentifier, const QSharedPointer<Database> &db) {
  QUuid dbUuid;
  QUuid entryUuid;

  if (!parseRecordIdentifier(recordIdentifier, dbUuid, entryUuid)) {
    return nullptr;
  }

  auto entry = db->rootGroup()->findEntryByUuid(entryUuid);
  if (!entry) {
    return nullptr;
  }

  QString username = entry->username();
  if (username.isEmpty()) {
    return nullptr;
  }

  QString password = entry->password();
  if (password.isEmpty()) {
    return nullptr;
  }

  NSString *objcUsername = username.toNSString();
  NSString *objcPassword = password.toNSString();

  ASPasswordCredential *passwordCredential =
      [[ASPasswordCredential alloc] initWithUser:objcUsername
                                        password:objcPassword];

  return passwordCredential;
}

ASPasswordCredentialIdentity *
AutoFillService::getPasswordCredentialIdentityFromEntry(const Entry *entry,
                                                        const QUuid dbUuid,
                                                        const QString dbName) {
  QString username = entry->username();
  QString password = entry->password();

  if (username.isEmpty() || password.isEmpty()) {
    return nullptr;
  }

  auto *serviceIdentifier = getCredentialServiceIdentifierFromEntry(entry);
  if (!serviceIdentifier) {
    return nullptr;
  }

  QString title = entry->title();
  if (title.isEmpty()) {
    return nullptr;
  }

  NSString *userString = (title + " (" + dbName + ")").toNSString();

  NSString *recordIdentifier = recordIdentifierForEntry(entry, dbUuid);

  ASPasswordCredentialIdentity *identity = [[ASPasswordCredentialIdentity alloc]
      initWithServiceIdentifier:serviceIdentifier
                           user:userString
               recordIdentifier:recordIdentifier];

  return identity;
}

ASOneTimeCodeCredential *AutoFillService::getOneTimeCodeCredentialFromIdentity(
    const ASOneTimeCodeCredentialIdentity *identity,
    const QSharedPointer<Database> &db) {
  NSString *recordIdentifier = identity.recordIdentifier;

  return getOneTimeCodeCredentialFromIdentity(recordIdentifier, db);
}

ASOneTimeCodeCredential *AutoFillService::getOneTimeCodeCredentialFromIdentity(
    const NSString *recordIdentifier, const QSharedPointer<Database> &db) {
  QUuid dbUuid;
  QUuid entryUuid;

  if (!parseRecordIdentifier(recordIdentifier, dbUuid, entryUuid)) {
    return nullptr;
  }

  auto entry = db->rootGroup()->findEntryByUuid(entryUuid);
  if (!entry) {
    return nullptr;
  }

  QString totp = entry->totp();
  if (totp.isEmpty()) {
    return nullptr;
  }

  ASOneTimeCodeCredential *oneTimeCodeCredential =
      [[ASOneTimeCodeCredential alloc] initWithCode:totp.toNSString()];

  return oneTimeCodeCredential;
}

ASPasskeyRegistrationCredential *
AutoFillService::createPasskeyRegistrationCredential(
    const ASPasskeyCredentialRequest *request,
    const QSharedPointer<Database> &db, Entry *existingEntry) {
  ASPasskeyCredentialIdentity *identity =
      static_cast<ASPasskeyCredentialIdentity *>(request.credentialIdentity);

  QByteArray clientDataHash = QByteArray::fromNSData(request.clientDataHash);

  NSNumber *firstAlgorithm = [request.supportedAlgorithms firstObject];
  WebAuthnAlgorithms algorithm = WebAuthnAlgorithms::ES256;

  if (firstAlgorithm != nil) {
    int rawAlg = [firstAlgorithm intValue];
    if (rawAlg == WebAuthnAlgorithms::ES256 ||
        rawAlg == WebAuthnAlgorithms::RS256 ||
        rawAlg == WebAuthnAlgorithms::EDDSA) {
      algorithm = static_cast<WebAuthnAlgorithms>(rawAlg);
    }
  }

  const auto privateKey =
      browserPasskeys()->buildCredentialPrivateKey(algorithm);

  QString rpId = QString::fromNSString(identity.relyingPartyIdentifier);
  QString extensions = QString("");
  auto authenticatorData =
      browserPasskeys()->buildAuthenticatorData(rpId, extensions, true);

  authenticatorData.append(browserMessageBuilder()->getArrayFromHexString(
      QStringLiteral("fdb141b25d84443e8a354698c205a502")));

  const auto credentialId =
      browserMessageBuilder()->getRandomBytesAsBase64(ID_BYTES);

  const char credentialLength[2] = {0x00, ID_BYTES};
  authenticatorData.append(QByteArray::fromRawData(credentialLength, 2));

  authenticatorData.append(QByteArray::fromBase64(
      credentialId.toUtf8(), QByteArray::Base64UrlEncoding));

  authenticatorData.append(privateKey.cborEncodedPublicKey);

  // const auto signature = browserPasskeys()->buildSignature(authenticatorData,
  // clientDataHash, QString(privateKey.privateKeyPem));

  // Make AttestationObject
  QCborMap attStmt;
  /*attStmt.insert(QStringLiteral("alg"), algorithm);
  attStmt.insert(QStringLiteral("sig"), signature);*/
  // TODO: Why should attstmt be empty for fmt none?

  QCborMap attestationObject;
  attestationObject.insert(QStringLiteral("fmt"), QStringLiteral("none"));
  attestationObject.insert(QStringLiteral("attStmt"), attStmt);
  attestationObject.insert(QStringLiteral("authData"), authenticatorData);

  QByteArray cborEncoded = QCborValue(attestationObject).toCbor();
  QString base64String = cborEncoded.toBase64();
  NSLog(@"Base64 Encoded CBOR: %@", base64String.toNSString());

  Group *rootGroup = db->rootGroup();
  Entry *entry = existingEntry;
  bool isNewEntry = entry == nullptr;
  if (isNewEntry) {
    entry = new Entry();
    entry->setUuid(QUuid::createUuid());
    entry->setGroup(rootGroup);
    entry->setIcon(13); // KEEPASSXCBROWSER_PASSKEY_ICON
  }

  entry->setTitle(
      QObject::tr("%1 (Passkey)")
          .arg(QString::fromNSString(identity.relyingPartyIdentifier)));
  entry->setUsername(QString::fromNSString(identity.userName));
  entry->setUrl(QString::fromNSString(identity.relyingPartyIdentifier));

  entry->beginUpdate();

  entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_USERNAME,
                           QString::fromNSString(identity.userName));
  entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID,
                           credentialId, true);
  entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM,
                           QString(privateKey.privateKeyPem), true);
  entry->attributes()->set(
      EntryAttributes::KPEX_PASSKEY_RELYING_PARTY,
      QString::fromNSString(identity.relyingPartyIdentifier));
  entry->attributes()->set(EntryAttributes::KPEX_PASSKEY_USER_HANDLE,
                           QByteArray::fromNSData(identity.userHandle), true);
  entry->addTag(QObject::tr("Passkey"));

  entry->endUpdate();

  if (isNewEntry) {
    // Discard the blank pre-creation history snapshot beginUpdate() recorded;
    // an update to an existing entry keeps its real history instead.
    entry->removeHistoryItems(entry->historyItems());
  }

  QString errorMessage;
  if (!db->save(Database::Atomic, {},
                &errorMessage)) { // TODO: What happens if saving in app
                                  // extension while the db is open in main app
    return nil;
  }

  ASPasskeyRegistrationCredential *credential = [ASPasskeyRegistrationCredential
      credentialWithRelyingParty:identity.relyingPartyIdentifier
                  clientDataHash:request.clientDataHash
                    credentialID:QByteArray::fromBase64(
                                     credentialId.toUtf8(),
                                     QByteArray::Base64UrlEncoding)
                                     .toNSData()
               attestationObject:cborEncoded.toNSData()];

  return credential;

  /*NSData *clientDataHash = request.clientDataHash;
  NSString *userVerificationPreference = request.userVerificationPreference;
  NSArray<NSNumber *> *supportedAlgorithms = request.supportedAlgorithms;

  NSString *userName = identity.userName;
  NSData *userHandle = identity.userHandle;
  NSString *relyingPartyIdentifier = identity.relyingPartyIdentifier;
  NSData *credentialID = identity.credentialID;
  NSString *recordIdentifier = identity.recordIdentifier;*/
}

ASPasskeyAssertionCredential *
AutoFillService::getPasskeyCredentialFromPasskeyRequest(
    const ASPasskeyCredentialRequest *request,
    const QSharedPointer<Database> &db) {
  ASPasskeyCredentialIdentity *identity =
      static_cast<ASPasskeyCredentialIdentity *>(request.credentialIdentity);
  QUuid dbUuid;
  QUuid entryUuid;

  if (!parseRecordIdentifier(identity.recordIdentifier, dbUuid, entryUuid)) {
    return nullptr;
  }

  auto entry = db->rootGroup()->findEntryByUuid(entryUuid);
  if (!entry) {
    return nullptr;
  }

  const QString privateKeyPem =
      entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM);

  QByteArray clientDataHash = QByteArray::fromNSData(request.clientDataHash);

  QString rpId = QString::fromNSString(identity.relyingPartyIdentifier);
  QString extensions = QString("");

  const auto authenticatorData =
      browserPasskeys()->buildAuthenticatorData(rpId, extensions);
  const auto signature = browserPasskeys()->buildSignature(
      authenticatorData, clientDataHash, privateKeyPem);

  ASPasskeyAssertionCredential *credential = [ASPasskeyAssertionCredential
      credentialWithUserHandle:identity.userHandle
                  relyingParty:identity.relyingPartyIdentifier
                     signature:signature.toNSData()
                clientDataHash:request.clientDataHash
             authenticatorData:authenticatorData.toNSData()
                  credentialID:identity.credentialID];

  return credential;
}

ASPasswordCredential *AutoFillService::getPasswordCredentialFromPasswordRequest(
    const ASPasswordCredentialRequest *request,
    const QSharedPointer<Database> &db) {
  ASPasswordCredentialIdentity *identity =
      static_cast<ASPasswordCredentialIdentity *>(request.credentialIdentity);
  QUuid dbUuid;
  QUuid entryUuid;

  if (!parseRecordIdentifier(identity.recordIdentifier, dbUuid, entryUuid)) {
    return nullptr;
  }

  auto entry = db->rootGroup()->findEntryByUuid(entryUuid);
  if (!entry) {
    return nullptr;
  }

  const QString username =
      entry->attributes()->value(EntryAttributes::UserNameKey);
  const QString password =
      entry->attributes()->value(EntryAttributes::PasswordKey);

  ASPasswordCredential *credential =
      [ASPasswordCredential credentialWithUser:username.toNSString()
                                      password:password.toNSString()];

  return credential;
}

ASPasswordCredential *
AutoFillService::getPasswordCredentialFromEntry(const Entry *entry) {
  QString username = entry->username();
  QString password = entry->password();

  if (username.isEmpty() || password.isEmpty()) {
    return nullptr;
  }

  return [ASPasswordCredential credentialWithUser:username.toNSString()
                                          password:password.toNSString()];
}

ASOneTimeCodeCredential *
AutoFillService::getOneTimeCodeCredentialFromEntry(const Entry *entry) {
  QString totp = entry->totp();
  if (totp.isEmpty()) {
    return nullptr;
  }

  return [[ASOneTimeCodeCredential alloc] initWithCode:totp.toNSString()];
}

ASPasskeyAssertionCredential *AutoFillService::getPasskeyCredentialFromEntry(
    const Entry *entry, NSData *clientDataHash,
    const ASPasskeyCredentialRequestParameters *requestParameters) {
  if (!entry->hasPasskey()) {
    return nullptr;
  }

  const QString privateKeyPem =
      entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM);

  const QString credentialId =
      entry->attributes()->hasKey(
          EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
          ? entry->attributes()->value(
                EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
          : entry->attributes()->value(
                EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID);
  NSData *credentialID =
      browserMessageBuilder()->getArrayFromBase64(credentialId).toNSData();

  const QString userHandle =
      entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE);
  NSData *userHandleData =
      browserMessageBuilder()->getArrayFromBase64(userHandle).toNSData();

  QByteArray clientDataHashBytes = QByteArray::fromNSData(clientDataHash);
  QString rpId =
      QString::fromNSString(requestParameters.relyingPartyIdentifier);
  QString extensions = QString("");

  const auto authenticatorData =
      browserPasskeys()->buildAuthenticatorData(rpId, extensions);
  const auto signature = browserPasskeys()->buildSignature(
      authenticatorData, clientDataHashBytes, privateKeyPem);

  return [ASPasskeyAssertionCredential
      credentialWithUserHandle:userHandleData
                  relyingParty:requestParameters.relyingPartyIdentifier
                     signature:signature.toNSData()
                clientDataHash:clientDataHash
             authenticatorData:authenticatorData.toNSData()
                  credentialID:credentialID];
}

QList<Entry *>
AutoFillService::searchEntries(const QSharedPointer<Database> &db,
                               const QString &siteUrl, bool passkeyOnly,
                               bool totpOnly) {
  QList<Entry *> entries;
  auto *rootGroup = db->rootGroup();
  if (!rootGroup) {
    return entries;
  }

  for (const auto &group : rootGroup->groupsRecursive(true)) {
    const auto groupOptionHideEntry =
        group->resolveCustomDataTriState(BrowserService::OPTION_HIDE_ENTRY);
    if (group->isRecycled() || groupOptionHideEntry == Group::Enable) {
      continue;
    }

    for (auto *entry : group->entries()) {
      if (entry->isRecycled() ||
          (groupOptionHideEntry == Group::Inherit &&
           entry->customData()->contains(BrowserService::OPTION_HIDE_ENTRY) &&
           entry->customData()->value(BrowserService::OPTION_HIDE_ENTRY) ==
               TRUE_STR)) {
        continue;
      }

      if (passkeyOnly) {
        if (!entry->hasPasskey() ||
            entry->attributes()->value(
                EntryAttributes::KPEX_PASSKEY_RELYING_PARTY) != siteUrl) {
          continue;
        }
      } else if (totpOnly) {
        if (!entry->hasTotp() || !shouldIncludeEntryForUrl(entry, siteUrl)) {
          continue;
        }
      } else if (!shouldIncludeEntryForUrl(entry, siteUrl)) {
        continue;
      }

      if (!entries.contains(entry)) {
        entries.append(entry);
      }
    }
  }

  return entries;
}

QList<Entry *> AutoFillService::allEntries(const QSharedPointer<Database> &db,
                                           bool passkeyOnly, bool totpOnly) {
  QList<Entry *> entries;
  auto *rootGroup = db->rootGroup();
  if (!rootGroup) {
    return entries;
  }

  for (const auto &group : rootGroup->groupsRecursive(true)) {
    const auto groupOptionHideEntry =
        group->resolveCustomDataTriState(BrowserService::OPTION_HIDE_ENTRY);
    if (group->isRecycled() || groupOptionHideEntry == Group::Enable) {
      continue;
    }

    for (auto *entry : group->entries()) {
      if (entry->isRecycled() ||
          (groupOptionHideEntry == Group::Inherit &&
           entry->customData()->contains(BrowserService::OPTION_HIDE_ENTRY) &&
           entry->customData()->value(BrowserService::OPTION_HIDE_ENTRY) ==
               TRUE_STR)) {
        continue;
      }

      if (passkeyOnly && !entry->hasPasskey()) {
        continue;
      }
      if (totpOnly && !entry->hasTotp()) {
        continue;
      }
      if (!passkeyOnly && !totpOnly && entry->password().isEmpty()) {
        continue;
      }

      entries.append(entry);
    }
  }

  return entries;
}

bool AutoFillService::shouldIncludeEntryForUrl(const Entry *entry,
                                               const QString &siteUrl) {
  if (handleURL(entry->resolveUrl(), siteUrl)) {
    return true;
  }

  const auto additionalUrls = entry->getAdditionalUrls();
  for (const auto &additionalUrl : additionalUrls) {
    if (handleURL(additionalUrl, siteUrl, true)) {
      return true;
    }
  }

  return false;
}

bool AutoFillService::handleURL(const QString &entryUrl,
                                const QString &siteUrl,
                                bool allowWildcards) {
  if (entryUrl.isEmpty()) {
    return false;
  }

  bool isWildcardUrl = false;
  auto tempUrl = entryUrl;

  if (allowWildcards) {
    if (entryUrl.startsWith("\"") && entryUrl.endsWith("\"")) {
      return QStringView{entryUrl}.mid(1, entryUrl.length() - 2) == siteUrl;
    }

    isWildcardUrl = entryUrl.contains("*");
    if (isWildcardUrl) {
      tempUrl = tempUrl.replace("*", UrlTools::URL_WILDCARD);
    }
  }

  QUrl entryQUrl;
  if (entryUrl.contains("://")) {
    entryQUrl = tempUrl;
  } else {
    entryQUrl = QUrl::fromUserInput(tempUrl);

    if (browserSettings()->matchUrlScheme()) {
      entryQUrl.setScheme("https");
    }
  }

  if (entryQUrl.host().isEmpty()) {
    return false;
  }

  QUrl siteQUrl(siteUrl);
  if (entryQUrl.port() > 0 && entryQUrl.port() != siteQUrl.port()) {
    return false;
  }

  if (browserSettings()->matchUrlScheme() && !entryQUrl.scheme().isEmpty() &&
      entryQUrl.scheme().compare(siteQUrl.scheme()) != 0) {
    return false;
  }

  QRegularExpression re("[<>\\^`{|}]");
  if (re.match(entryUrl).hasMatch()) {
    return false;
  }

  if (isWildcardUrl) {
    // Wildcard entries are rare in AutoFill's offline matching context;
    // treat them as a base-domain match rather than porting BrowserService's
    // full regex-based wildcard expansion.
    return urlTools()->getBaseDomainFromUrl(siteQUrl.host()) ==
           urlTools()->getBaseDomainFromUrl(entryQUrl.host());
  }

  if (urlTools()->getBaseDomainFromUrl(siteQUrl.host()) !=
      urlTools()->getBaseDomainFromUrl(entryQUrl.host())) {
    return false;
  }

  return siteQUrl.host().endsWith(entryQUrl.host());
}

ASOneTimeCodeCredentialIdentity *
AutoFillService::getOneTimeCodeCredentialIdentityFromEntry(const Entry *entry,
                                                           const QUuid dbUuid) {
  if (!entry->hasTotp()) {
    return nullptr;
  }

  auto *serviceIdentifier = getCredentialServiceIdentifierFromEntry(entry);
  if (!serviceIdentifier) {
    return nullptr;
  }

  QString title = entry->title();
  if (title.isEmpty()) {
    return nullptr;
  }

  NSString *userString = title.toNSString();

  NSString *recordIdentifier = recordIdentifierForEntry(entry, dbUuid);

  ASOneTimeCodeCredentialIdentity *identity =
      [[ASOneTimeCodeCredentialIdentity alloc]
          initWithServiceIdentifier:serviceIdentifier
                              label:userString
                   recordIdentifier:recordIdentifier];

  return identity;
}

ASPasskeyCredentialIdentity *
AutoFillService::getPasskeyCredentialIdentityFromEntry(const Entry *entry,
                                                       const QUuid dbUuid) {
  if (!entry->hasPasskey()) {
    return nullptr;
  }

  NSString *relyingPartyIdentifier =
      entry->attributes()
          ->value(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY)
          .toNSString();
  NSString *userName = entry->attributes()
                           ->value(EntryAttributes::KPEX_PASSKEY_USERNAME)
                           .toNSString();

  const QString credentialId =
      entry->attributes()->hasKey(
          EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
          ? entry->attributes()->value(
                EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
          : entry->attributes()->value(
                EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID);

  NSData *credentialID =
      browserMessageBuilder()->getArrayFromBase64(credentialId).toNSData();

  const QString userHandle =
      entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE);
  NSData *userHandleData =
      browserMessageBuilder()->getArrayFromBase64(userHandle).toNSData();

  NSString *recordIdentifier = recordIdentifierForEntry(entry, dbUuid);

  ASPasskeyCredentialIdentity *identity = [ASPasskeyCredentialIdentity
      identityWithRelyingPartyIdentifier:relyingPartyIdentifier
                                userName:userName
                            credentialID:credentialID
                              userHandle:userHandleData
                        recordIdentifier:recordIdentifier];

  return identity;
}

ASCredentialServiceIdentifier *
AutoFillService::getCredentialServiceIdentifierFromEntry(const Entry *entry) {
  QString webUrl = entry->webUrl();

  if (webUrl.isEmpty()) {
    return nullptr;
  }

  NSString *serviceIdentifierString = webUrl.toNSString();

  ASCredentialServiceIdentifier *serviceIdentifier;

  /*if (@available(macOS 26.2, *)) {
    serviceIdentifier = [[ASCredentialServiceIdentifier alloc]
        initWithIdentifier:serviceIdentifierString
                      type:ASCredentialServiceIdentifierTypeURL
               displayName:@"KeePassXC Test"];
  } else {*/
    serviceIdentifier = [[ASCredentialServiceIdentifier alloc]
        initWithIdentifier:serviceIdentifierString
                      type:ASCredentialServiceIdentifierTypeURL];
  //}

  return serviceIdentifier;
}

NSString *AutoFillService::recordIdentifierForEntry(const Entry *entry,
                                                    const QUuid dbUuid) {
  QString dbUuidHex = Tools::uuidToHex(dbUuid);
  QString entryUuid = entry->uuidToHex();

  return QString("%1:%2").arg(dbUuidHex, entryUuid).toNSString();
}

bool AutoFillService::parseRecordIdentifier(const NSString *recordIdentifier,
                                            QUuid &dbUuid, QUuid &entryUuid) {
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