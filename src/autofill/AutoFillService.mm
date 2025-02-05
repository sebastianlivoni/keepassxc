#include "AutoFillService.h"

#include <AuthenticationServices/AuthenticationServices.h>
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
  ASPasswordCredential *passwordCredential =
      [[ASPasswordCredential alloc] initWithUser:@"username"
                                        password:@"password"];

  return passwordCredential;
}

ASOneTimeCodeCredential *AutoFillService::getOneTimeCodeCredentialFromIdentity(
    const ASOneTimeCodeCredentialIdentity *identity) {
  ASOneTimeCodeCredential *oneTimeCodeCredential =
      [[ASOneTimeCodeCredential alloc] initWithCode:@"123456"];

  return oneTimeCodeCredential;
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
  return [entry->uuid().toNSUUID() UUIDString];
}