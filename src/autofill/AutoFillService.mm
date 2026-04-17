#include "AutoFillService.h"

#include <Foundation/Foundation.h>
#include <QApplication>

#include "browser/BrowserMessageBuilder.h"
#include "browser/BrowserPasskeys.h"
#include "browser/BrowserPasskeysClient.h"
#include "core/Tools.h"
#include "quickunlock/QuickUnlockInterface.h"

#include <AuthenticationServices/AuthenticationServices.h>

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QString>

AutoFillService *AutoFillService::instance() {
  static AutoFillService instance;
  return &instance;
}

void AutoFillService::saveCredentialStore(const QSharedPointer<Database> &db) {}

void AutoFillService::replaceCredentialStore(
    const QSharedPointer<Database> &db) {
  [ASCredentialIdentityStore
          .sharedStore getCredentialIdentityStoreStateWithCompletion:^(
                           ASCredentialIdentityStoreState *state) {
    if (state.isEnabled) {
      NSMutableArray *credentialIdentities = [NSMutableArray array];

      for (Entry *entry : db->rootGroup()->entriesRecursive()) {
        if (entry->isRecycled()) {
          continue;
        }

        auto *passwordCredentialIdentity =
            getPasswordCredentialIdentityFromEntry(entry);

        if (passwordCredentialIdentity) {
          [credentialIdentities addObject:passwordCredentialIdentity];
        }

        auto *oneTimeCodeCredentialIdentity =
            getOneTimeCodeCredentialIdentityFromEntry(entry);

        if (oneTimeCodeCredentialIdentity) {
          [credentialIdentities addObject:oneTimeCodeCredentialIdentity];
        }

        auto *passkeyCredentialIdentity =
            getPasskeyCredentialIdentityFromEntry(entry);

        if (passkeyCredentialIdentity) {
          [credentialIdentities addObject:passkeyCredentialIdentity];
        }
      }

      [ASCredentialIdentityStore.sharedStore
          replaceCredentialIdentityEntries:credentialIdentities
                                completion:^(BOOL success, NSError *error) {
                                  if (success) {
                                    NSLog(@"Successfully replaced "
                                          @"credential identities. (%lu items)",
                                          credentialIdentities.count);
                                  } else {
                                    NSLog(@"Failed to replace credential "
                                          @"identities: %@",
                                          error.localizedDescription);
                                  }
                                }];
    }
  }];
}

void AutoFillService::resetCredentialStore() {
  [ASCredentialIdentityStore.sharedStore
      getCredentialIdentityStoreStateWithCompletion:^(
          ASCredentialIdentityStoreState *state) {
        if (state.isEnabled) {
          [ASCredentialIdentityStore.sharedStore
              removeAllCredentialIdentitiesWithCompletion:nil];
        }
      }];
}

ASPasswordCredential *AutoFillService::getPasswordCredentialFromIdentity(
    const ASPasswordCredentialIdentity *identity,
    const QSharedPointer<Database> &db) {
  NSString *recordIdentifier = identity.recordIdentifier;

  return getPasswordCredentialFromIdentity(recordIdentifier, db);
}

ASPasswordCredential *AutoFillService::getPasswordCredentialFromIdentity(
    const NSString *recordIdentifier, const QSharedPointer<Database> &db) {
  QString uuidHex = QString::fromNSString(recordIdentifier);

  auto entry = db->rootGroup()->findEntryByUuid(Tools::hexToUuid(uuidHex));
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
AutoFillService::getPasswordCredentialIdentityFromEntry(const Entry *entry) {
  NSString *uuidString = uuidStringFromEntry(entry);

  auto *serviceIdentifier = getCredentialServiceIdentifierFromEntry(entry);
  if (!serviceIdentifier) {
    return nullptr;
  }

  QString title = entry->title();
  if (title.isEmpty()) {
    return nullptr;
  }

  NSString *userString = title.toNSString();

  ASPasswordCredentialIdentity *identity = [[ASPasswordCredentialIdentity alloc]
      initWithServiceIdentifier:serviceIdentifier
                           user:userString
               recordIdentifier:uuidString];

  return identity;
}

ASOneTimeCodeCredential *AutoFillService::getOneTimeCodeCredentialFromIdentity(
    const ASOneTimeCodeCredentialIdentity *identity,
    const QSharedPointer<Database> &db) {
        NSString *recordIdentifier = identity.recordIdentifier;

        return getOneTimeCodeCredentialFromIdentity(recordIdentifier, db);
    }

ASOneTimeCodeCredential *AutoFillService::getOneTimeCodeCredentialFromIdentity(
    const NSString *recordIdentifier,
    const QSharedPointer<Database> &db) {
  QString uuidHex = QString::fromNSString(recordIdentifier);

  auto entry = db->rootGroup()->findEntryByUuid(Tools::hexToUuid(uuidHex));
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
    const QSharedPointer<Database> &db) {
  ASPasskeyCredentialIdentity *identity =
      (ASPasskeyCredentialIdentity *)request.credentialIdentity;

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

  // TODO: Save the credentials in a entry
  // TODO: Add identity to store

  Group *rootGroup = db->rootGroup();
  auto *entry = new Entry();
  entry->setUuid(QUuid::createUuid());
  entry->setGroup(rootGroup);
  entry->setTitle(
      QObject::tr("%1 (Passkey)")
          .arg(QString::fromNSString(identity.relyingPartyIdentifier)));
  entry->setUsername(QString::fromNSString(identity.userName));
  entry->setUrl(QString::fromNSString(identity.relyingPartyIdentifier));
  entry->setIcon(13); // KEEPASSXCBROWSER_PASSKEY_ICON

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

  entry->removeHistoryItems(entry->historyItems());

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

  replaceCredentialStore(db);

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
      (ASPasskeyCredentialIdentity *)request.credentialIdentity;
  NSString *recordIdentifier = identity.recordIdentifier;
  QString uuidHex = QString::fromNSString(recordIdentifier);

  auto entry = db->rootGroup()->findEntryByUuid(Tools::hexToUuid(uuidHex));
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

ASOneTimeCodeCredentialIdentity *
AutoFillService::getOneTimeCodeCredentialIdentityFromEntry(const Entry *entry) {
  if (!entry->hasTotp()) {
    return nullptr;
  }

  NSString *uuidString = uuidStringFromEntry(entry);

  auto *serviceIdentifier = getCredentialServiceIdentifierFromEntry(entry);
  if (!serviceIdentifier) {
    return nullptr;
  }

  QString title = entry->title();
  if (title.isEmpty()) {
    return nullptr;
  }

  NSString *userString = title.toNSString();

  ASOneTimeCodeCredentialIdentity *identity =
      [[ASOneTimeCodeCredentialIdentity alloc]
          initWithServiceIdentifier:serviceIdentifier
                              label:userString
                   recordIdentifier:uuidString];

  return identity;
}

ASPasskeyCredentialIdentity *
AutoFillService::getPasskeyCredentialIdentityFromEntry(const Entry *entry) {
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

  NSString *uuidString = uuidStringFromEntry(entry);

  ASPasskeyCredentialIdentity *identity = [ASPasskeyCredentialIdentity
      identityWithRelyingPartyIdentifier:relyingPartyIdentifier
                                userName:userName
                            credentialID:credentialID
                              userHandle:userHandleData
                        recordIdentifier:uuidString];

  return identity;
}

ASCredentialServiceIdentifier *
AutoFillService::getCredentialServiceIdentifierFromEntry(const Entry *entry) {
  QString webUrl = entry->webUrl();

  if (webUrl.isEmpty()) {
    return nullptr;
  }

  NSString *serviceIdentifierString = webUrl.toNSString();

  ASCredentialServiceIdentifier *serviceIdentifier =
      [[ASCredentialServiceIdentifier alloc]
          initWithIdentifier:serviceIdentifierString
                        type:ASCredentialServiceIdentifierTypeURL];

  return serviceIdentifier;
}

NSString *AutoFillService::uuidStringFromEntry(const Entry *entry) {
  QString uuidHex = entry->uuidToHex();
  NSString *nsString = uuidHex.toNSString();
  return nsString;
}
