#include "AutoFillService.h"

#include <QApplication>

#include "browser/BrowserMessageBuilder.h"
#include "browser/BrowserPasskeysClient.h"
#include "browser/BrowserPasskeys.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <QString>
#include <QJsonObject>
#include <QJsonDocument>
#include "core/Tools.h"
#include "browser/PasskeyUtils.h"

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

        auto *passkeyCredentialIdentity = getPasskeyCredentialIdentityFromEntry(entry);

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
    const ASPasswordCredentialIdentity *identity) {

  auto db = QSharedPointer<Database>::create();
  auto key = QSharedPointer<CompositeKey>::create();
  auto passwordKey = QSharedPointer<PasswordKey>::create("a");
  key->addKey(passwordKey);
  
  QString error;
  if (db->open("/Users/seb/Downloads/Adgangskoder.kdbx", key, &error)) {
    NSString *recordIdentifier = identity.recordIdentifier;

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
  } else {
    return nullptr;
  }
}


ASPasswordCredentialIdentity* AutoFillService::getPasswordCredentialIdentityFromEntry(const Entry *entry) {
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
  const ASOneTimeCodeCredentialIdentity *identity) {

  auto db = QSharedPointer<Database>::create();
  auto key = QSharedPointer<CompositeKey>::create();
  auto passwordKey = QSharedPointer<PasswordKey>::create("a");
  key->addKey(passwordKey);
  
  QString error;
  if (db->open("/Users/seb/Downloads/Adgangskoder.kdbx", key, &error)) {
    NSString *recordIdentifier = identity.recordIdentifier;

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
  } else {
    return nullptr;
  }
}

ASPasskeyRegistrationCredential* AutoFillService::createPasskeyRegistrationCredential(const ASPasskeyCredentialRequest *request) {
  ASPasskeyCredentialIdentity *identity = (ASPasskeyCredentialIdentity *)request.credentialIdentity;

  NSData *clientDataHash = request.clientDataHash;
  NSString *userVerificationPreference = request.userVerificationPreference;
  NSArray<NSNumber *> *supportedAlgorithms = request.supportedAlgorithms;

  NSString *userName = identity.userName;
  NSData *userHandle = identity.userHandle;
  NSString *relyingPartyIdentifier = identity.relyingPartyIdentifier;
  NSData *credentialID = identity.credentialID;
  NSString *recordIdentifier = identity.recordIdentifier;
}

ASPasskeyAssertionCredential* AutoFillService::getPasskeyCredentialFromPasskeyRequest(const ASPasskeyCredentialRequest *request) {
  ASPasskeyCredentialIdentity *identity = (ASPasskeyCredentialIdentity *)request.credentialIdentity;

  auto db = QSharedPointer<Database>::create();
  auto key = QSharedPointer<CompositeKey>::create();
  auto passwordKey = QSharedPointer<PasswordKey>::create("a");
  key->addKey(passwordKey);
  
  QString error;
  if (db->open("/Users/seb/Downloads/Adgangskoder.kdbx", key, &error)) {
    NSString *recordIdentifier = identity.recordIdentifier;
    QString uuidHex = QString::fromNSString(recordIdentifier);
    
    auto entry = db->rootGroup()->findEntryByUuid(Tools::hexToUuid(uuidHex));
    if (!entry) {
      return nullptr;
    }

    const QString privateKeyPem = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_PRIVATE_KEY_PEM);

    QByteArray clientDataHash = QByteArray::fromNSData(request.clientDataHash);

    QString rpId = QString::fromNSString(identity.relyingPartyIdentifier);
    QString extensions = QString("");

    const auto authenticatorData = browserPasskeys()->buildAuthenticatorData(rpId, extensions);
    const auto signature = browserPasskeys()->buildSignature(authenticatorData, clientDataHash, privateKeyPem);

    ASPasskeyAssertionCredential *credential = [ASPasskeyAssertionCredential credentialWithUserHandle:identity.userHandle
                                                                                       relyingParty:identity.relyingPartyIdentifier
                                                                                          signature:signature.toNSData()
                                                                                     clientDataHash:request.clientDataHash
                                                                                  authenticatorData:authenticatorData.toNSData()
                                                                                       credentialID:identity.credentialID];

    return credential;
  }
  
  
  return nullptr;
}

ASOneTimeCodeCredentialIdentity* AutoFillService::getOneTimeCodeCredentialIdentityFromEntry(const Entry *entry) {
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

ASPasskeyCredentialIdentity* AutoFillService::getPasskeyCredentialIdentityFromEntry(const Entry *entry) {
  if (!entry->hasPasskey()) {
    return nullptr;
  }

  NSString* relyingPartyIdentifier = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY).toNSString();
  NSString* userName = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USERNAME).toNSString();
  
  const QString credentialId = entry->attributes()->hasKey(EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
               ? entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_GENERATED_USER_ID)
               : entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_CREDENTIAL_ID);

  NSData *credentialID = browserMessageBuilder()->getArrayFromBase64(credentialId).toNSData();

  const QString userHandle = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE);
  NSData *userHandleData = browserMessageBuilder()->getArrayFromBase64(userHandle).toNSData();

  NSString *uuidString = uuidStringFromEntry(entry);

  ASPasskeyCredentialIdentity *identity = [ASPasskeyCredentialIdentity identityWithRelyingPartyIdentifier:relyingPartyIdentifier
                                                                                        userName:userName
                                                                                    credentialID:credentialID
                                                                                      userHandle:userHandleData
                                                                                recordIdentifier:uuidString];

  return identity;
}

ASCredentialServiceIdentifier* AutoFillService::getCredentialServiceIdentifierFromEntry(const Entry *entry) {
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

NSString* AutoFillService::uuidStringFromEntry(const Entry *entry) {
  QString uuidHex = entry->uuidToHex();
  NSString* nsString = uuidHex.toNSString();
  return nsString;
}
