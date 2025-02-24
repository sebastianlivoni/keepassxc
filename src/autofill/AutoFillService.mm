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

  int argc = 0;
  char *argv[] = {};
  new QCoreApplication(argc, argv);

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

  int argc = 0;
  char *argv[] = {};
  new QCoreApplication(argc, argv);

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

  //const auto publicKeyCredentials = browserPasskeys()->buildRegisterPublicKeyCredential(credentialCreationOptions);
}

ASPasskeyAssertionCredential* AutoFillService::getPasskeyCredentialFromPasskeyRequest(const ASPasskeyCredentialRequest *request) {
  ASPasskeyCredentialIdentity *identity = (ASPasskeyCredentialIdentity *)request.credentialIdentity;

  NSData *challenge = request.clientDataHash;
  QByteArray challengeQ = QByteArray::fromNSData(challenge);
  QString challengeString = browserMessageBuilder()->getBase64FromArray(challengeQ);
  //NSString *challengeString = [challenge base64EncodedStringWithOptions:0];

  int argc = 0;
  char *argv[] = {};
  new QCoreApplication(argc, argv);

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
    const QString origin = QString::fromNSString(identity.relyingPartyIdentifier); 
    const QString credentialId = passkeyUtils()->getCredentialIdFromEntry(entry);

    const QString PublicKeyCredentialRequestOptions = QString(R"(
        {
            "allowCredentials": [
                {
                    "id": "%1",
                    "transports": ["internal"],
                    "type": "public-key"
                }
            ],
            "challenge": "%2",
            "rpId": "%3",
            "timeout": 60000,
            "userVerification": "required"
        }
    )")
    .arg(credentialId)
    .arg(challengeString)
    .arg(origin); // todo user verification mapping

    /*const auto privateKeyPem = QString("-----BEGIN PRIVATE KEY-----"
                                       "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg5DX2R6I37nMSZqCp"
                                       "XfHlE3UeitkGGE03FqGsdfxIBoOhRANCAAQG7K80W2KRYW0ZWQOmUCrKMcSVqGnl"
                                       "8Ifl1LgyzQiF3eLuf+kPDukdB4NKAwnbQiSxC9Ml/xgy4VOZtx1CBOeD"
                                       "-----END PRIVATE KEY-----");
    const auto origin = QString("https://webauthn.io");
    const auto credentialId = QString("yrzFJ5lwcpTwYMOdXSmxF5b5cYQlqBMzbbU_d-oFLO8");

    const QString PublicKeyCredentialRequestOptions = R"(
        {
            "allowCredentials": [
                {
                    "id": "yrzFJ5lwcpTwYMOdXSmxF5b5cYQlqBMzbbU_d-oFLO8",
                    "transports": ["internal"],
                    "type": "public-key"
                }
            ],
            "challenge": "9z36vTfQTL95Lf7WnZgyte7ohGeF-XRiLxkL-LuGU1zopRmMIUA1LVwzGpyIm1fOBn1QnRa0QH27ADAaJGHysQ",
            "rpId": "webauthn.io",
            "timeout": 60000,
            "userVerification": "required"
        }
    )";*/

    const auto publicKeyCredentialRequestOptions = browserMessageBuilder()->getJsonObject(PublicKeyCredentialRequestOptions.toUtf8());

    QJsonObject assertionOptions;
    const auto assertionResult = browserPasskeysClient()->getAssertionOptions(publicKeyCredentialRequestOptions, origin, &assertionOptions);

    QJsonDocument doc = QJsonDocument(assertionOptions);
    QString strJson1 = doc.toJson(QJsonDocument::Compact);
    NSLog(@"Request: %@", strJson1.toNSString());

    if (assertionResult != 0) {
      return nullptr;
    }

    const auto userHandle = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE);

    auto publicKeyCredential = browserPasskeys()->buildGetPublicKeyCredential(assertionOptions, credentialId, userHandle, privateKeyPem);
    auto response = publicKeyCredential["response"].toObject();

    QJsonDocument doc2 = QJsonDocument(response);
    QString strJson2 = doc2.toJson(QJsonDocument::Compact);
    NSLog(@"Response: %@", strJson2.toNSString());

    NSData *authenticatorData = browserMessageBuilder()->base64Decode(response["authenticatorData"].toString()).toNSData();
    NSData *clientDataJSON = browserMessageBuilder()->base64Decode(response["clientDataJSON"].toString()).toNSData();
    NSData *signature = browserMessageBuilder()->base64Decode(response["signature"].toString()).toNSData();

    NSString *relyingPartyIdentifier = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_RELYING_PARTY).toNSString();

    NSData *userHandleData = browserMessageBuilder()->base64Decode(userHandle).toNSData();
    NSData *credentialID = browserMessageBuilder()->base64Decode(credentialId).toNSData();

    ASPasskeyAssertionCredential *credential = [ASPasskeyAssertionCredential credentialWithUserHandle:userHandleData
                                                                                       relyingParty:relyingPartyIdentifier
                                                                                          signature:signature
                                                                                     clientDataHash:clientDataJSON
                                                                                  authenticatorData:authenticatorData
                                                                                       credentialID:credentialID];

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

  NSData *credentialID = browserMessageBuilder()->base64Decode(credentialId).toNSData();

  const QString userHandle = entry->attributes()->value(EntryAttributes::KPEX_PASSKEY_USER_HANDLE);
  NSData *userHandleData = browserMessageBuilder()->base64Decode(userHandle).toNSData();

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
