#include "CredentialProviderViewController.h"

#include <QApplication>
#include <QMacNativeWidget>
#include <QVBoxLayout>
#include <QPushButton>

#include "AutoFillService.h"
#include "AutoFillViewController.h"
#include "ExtensionConfigurationWidget.h"
#include "CredentialListWidget.h"
#include "PasskeyRegistrationWidget.h"
#include "ProvidePasskeyWidget.h"

@implementation CredentialProviderViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  int argc = 0;
  char *argv[] = { nullptr };
  QApplication *qtApp = new QApplication(argc, argv);
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {
  QWidget* widget = new CredentialListWidget(self.extensionContext);

  [self embedQWidget:widget hideRootView:NO];
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers requestParameters:(ASPasskeyCredentialRequestParameters *) requestParameters {
  // TODO: This will be called for passkeys
  QWidget* widget = new CredentialListWidget(self.extensionContext);

  [self embedQWidget:widget hideRootView:NO];
}

- (void)prepareOneTimeCodeCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *) serviceIdentifiers {}

- (void)prepareInterfaceForPasskeyRegistration:(id<ASCredentialRequest>) registrationRequest {
  /*ASPasskeyCredentialRequest *passkeyRegistrationRequest = (ASPasskeyCredentialRequest *)registrationRequest;
  ASPasskeyCredentialIdentity *credentialIdentity = (ASPasskeyCredentialIdentity *)passkeyRegistrationRequest.credentialIdentity;

  QWidget* widget = new PasskeyRegistrationWidget(self.extensionContext);

  [self embedQWidget:widget hideRootView:NO];*/
  QWidget* widget = new QWidget(); // TODO: Why does the prompt refresh?
  [self embedQWidget:widget hideRootView:YES];

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    auto *passkeyCredential = autoFillService()->createPasskeyRegistrationCredential(registrationRequest);

    if (!passkeyCredential) {
      NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                            code:ASExtensionErrorCodeFailed
                                        userInfo:nil];
      [self.extensionContext cancelRequestWithError:error];
      return;
    }

    [self.extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
  });
}

- (void)prepareInterfaceToProvideCredentialForRequest:(id<ASCredentialRequest>) credentialRequest {
  /*ASPasskeyCredentialRequest *passkeyCredentialRequest = (ASPasskeyCredentialRequest *)credentialRequest;
  QWidget* widget = new ProvidePasskeyWidget(self.extensionContext, passkeyCredentialRequest);
  [self embedQWidget:widget];*/

  switch (credentialRequest.type) {
    case ASCredentialRequestTypePassword: {
      QWidget* widget = new QWidget(); // TODO: Why does the prompt refresh?
      [self embedQWidget:widget hideRootView:YES];

      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ASPasswordCredentialIdentity *credentialIdentity = (ASPasswordCredentialIdentity *)credentialRequest.credentialIdentity;
        ASPasswordCredential *passwordCredential = autoFillService()->getPasswordCredentialFromIdentity(credentialIdentity);

        if (!passwordCredential) {
          NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                                code:ASExtensionErrorCodeFailed
                                            userInfo:nil];
          [self.extensionContext cancelRequestWithError:error];
          return;
        }

        [self.extensionContext completeRequestWithSelectedCredential:passwordCredential completionHandler:nil];
      });
      break;
    }
    case ASCredentialRequestTypePasskeyAssertion: {
      QWidget* widget = new QWidget(); // TODO: Why does the prompt refresh?
      [self embedQWidget:widget hideRootView:YES];

      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        auto *passkeyCredential = autoFillService()->getPasskeyCredentialFromPasskeyRequest(credentialRequest);

        if (!passkeyCredential) {
          NSError *error = [NSError errorWithDomain:ASExtensionErrorDomain
                                                code:ASExtensionErrorCodeFailed
                                            userInfo:nil];
          [self.extensionContext cancelRequestWithError:error];
          return;
        }

        [self.extensionContext completeAssertionRequestWithSelectedPasskeyCredential:passkeyCredential completionHandler:nil];
      });
      break;
    }
  }
}

- (void)provideCredentialWithoutUserInteractionForRequest:(id<ASCredentialRequest>) credentialRequest {
  switch (credentialRequest.type) {
  case ASCredentialRequestTypePassword: {
    [self exitWithUserInteractionRequired];
    /*ASPasswordCredentialIdentity *credentialIdentity = (ASPasswordCredentialIdentity *)credentialRequest.credentialIdentity;
    ASPasswordCredential *passwordCredential = autoFillService()->getPasswordCredentialFromIdentity(credentialIdentity);

    [self.extensionContext completeRequestWithSelectedCredential:passwordCredential completionHandler:nil];*/
    break;
  }
  case ASCredentialRequestTypeOneTimeCode: {
    ASOneTimeCodeCredentialIdentity *credentialIdentity = (ASOneTimeCodeCredentialIdentity *)credentialRequest.credentialIdentity;
    ASOneTimeCodeCredential *oneTimeCodeCredential = autoFillService()->getOneTimeCodeCredentialFromIdentity(credentialIdentity);
    [self.extensionContext completeOneTimeCodeRequestWithSelectedCredential:oneTimeCodeCredential completionHandler:nil];
    break;
  }
  case ASCredentialRequestTypePasskeyAssertion: {
    [self exitWithUserInteractionRequired];
    break;
  }
  default:
    NSLog(@"Unhandled credential request type: %@", @(credentialRequest.type));
    break;
  }
}

// - (void)performPasskeyRegistrationWithoutUserInteractionIfPossible:(ASPasskeyCredentialRequest *) registrationRequest {}

- (void)embedQWidget:(QWidget *)widget hideRootView:(BOOL)hide {
  NSView* rootView = reinterpret_cast<NSView *>(widget->winId());
  if (hide) {
    rootView.frame = NSMakeRect(0, 0, 0, 0);
  }

  [self.view addSubview:rootView];

  self.view.translatesAutoresizingMaskIntoConstraints = NO;

  [NSLayoutConstraint activateConstraints:@[
    [self.view.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:0],
    [self.view.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:0],
    [self.view.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:0],
    [self.view.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:0]
  ]];

  [self.view.widthAnchor constraintEqualToConstant:rootView.frame.size.width].active = YES;
  [self.view.heightAnchor constraintEqualToConstant:rootView.frame.size.height].active = YES;
}

- (void)prepareInterfaceForExtensionConfiguration {
  QWidget* widget = new ExtensionConfigurationWidget(self.extensionContext);

  [self embedQWidget:widget hideRootView:NO];
}

- (void)exitWithUserInteractionRequired {
  [self.extensionContext
      cancelRequestWithError:
          [NSError errorWithDomain:ASExtensionErrorDomain
                              code:ASExtensionErrorCodeUserInteractionRequired
                          userInfo:nil]];
}

@end
