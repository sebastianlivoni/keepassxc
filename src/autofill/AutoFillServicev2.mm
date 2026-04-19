#include "AutoFillServiceV2.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <ServiceManagement/SMAppService.h>

#include "../gui/MainWindow.h"
#include "AutoFillService.h"

void AutoFillServiceV2::start() {
  NSError *agentError = nil;

  SMAppService *agentService = [SMAppService
      agentServiceWithPlistName:@"me.livoni.KeePassXC.AutoFillService.plist"];

  BOOL agentRegistered = [agentService registerAndReturnError:&agentError];

  if (!agentRegistered) {
    NSLog(@"Failed to register agent service: %@", agentError);
  } else {
    NSLog(@"Successfully registered agent service");
  }

  AutoFillXPCService *service = [[AutoFillXPCService alloc] init];
  [service start];
  m_xpcService = service;
}

AutoFillServiceV2 *AutoFillServiceV2::instance() {
  static AutoFillServiceV2 s_instance;
  return &s_instance;
}

void AutoFillServiceV2::getMessage(void (^reply)(NSString *__strong,
                                                 NSError *__strong)) {
  NSString *message = @"Hello from provider v2!";
  reply(message, nil);
}

void AutoFillServiceV2::fetchPasswordCredentialFromIdentity(
    ASPasswordCredentialIdentity *identity,
    void (^reply)(ASPasswordCredential *__strong credential, NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASPasswordCredential *passwordCredential =
          getPasswordCredentialFromIdentity(identity, database);

      reply(passwordCredential, nil);
    }
  }
}

void AutoFillServiceV2::fetchOneTimeCodeForIdentity(
    ASOneTimeCodeCredentialIdentity *identity,
    void (^reply)(ASOneTimeCodeCredential *__strong credential, NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASOneTimeCodeCredential *oneTimeCredential =
          getOneTimeCodeCredentialFromIdentity(identity, database);

      reply(oneTimeCredential, nil);
    }
  }
}

void AutoFillServiceV2::fetchPasskeyCredentialFromPasskeyRequest(
    ASPasskeyCredentialRequest *request,
    void (^reply)(ASPasskeyAssertionCredential *__strong credential, NSError *__strong error)) {
  if (auto *window = getMainWindow()) {
    for (auto *widget : window->getOpenDatabases()) {
      if (!widget || widget->isLocked()) {
        continue;
      }

      auto database = widget->database();
      if (database.isNull()) {
        continue;
      }

      ASPasskeyAssertionCredential *credential = getPasskeyCredentialFromPasskeyRequest(request, database);

      reply(credential, nil);
    }
  }
}
