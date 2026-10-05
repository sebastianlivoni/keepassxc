#include "extension/CredentialProviderViewController.h"

#include <AuthenticationServices/AuthenticationServices.h>
#include <Foundation/Foundation.h>
#include <Foundation/NSObjCRuntime.h>
#include <QApplication>

#include "extension/widgets/ConfirmationWidget.h"
#include "extension/widgets/CredentialListWidget.h"
#include "extension/widgets/PasskeyRegistrationWidget.h"

#include <os/log.h>

#include "common/AutoFillCodeSigning.h"
#include "extension/AutoFillExtensionApplication.h"
#include "helper/AutoFillHelperProtocol.h"

@interface CredentialProviderViewController ()

// The embedded Qt view, made first responder so it receives key events
@property(nonatomic, strong) NSView* rootView;
// Calls waiting for the endpoint lookup through the helper
@property(nonatomic, strong) NSMutableArray* pendingConnectionBlocks;
@property(nonatomic, assign) BOOL serviceConnectionResolved;
@property(nonatomic, strong) NSLayoutConstraint* widthConstraint;
@property(nonatomic, strong) NSLayoutConstraint* heightConstraint;

@end

@implementation CredentialProviderViewController

- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // One Qt application per extension process, which may serve several requests
        if (!qApp) {
            // Use the Qt plugins bundled in the containing app (KeePassXC.app/Contents/PlugIns,
            // which also holds this .appex); dev builds without bundled plugins keep Qt's default
            NSString* appPlugIns = NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.path;
            if ([NSFileManager.defaultManager
                    fileExistsAtPath:[appPlugIns stringByAppendingPathComponent:@"platforms"]]) {
                QCoreApplication::setLibraryPaths({QString::fromNSString(appPlugIns)});
            }

            // Qt keeps references to argc/argv for the application's lifetime
            static int argc = 0;
            static char* argv[] = {nullptr};
            new AutoFillExtensionApplication(argc, argv);
        }

        self.xpcClient = [[AutoFillXPCClient alloc] init];
        [self.xpcClient start];

        id proxy = [self.xpcClient.helperConnection remoteObjectProxyWithErrorHandler:^(NSError* error) {
            os_log_error(OS_LOG_DEFAULT, "[AutoFill] Helper connection error: %{public}@", error);
            [self resolveServiceConnection];
        }];

        [proxy getEndpoint:^(NSXPCListenerEndpoint* endpoint, NSError* error) {
            if (error) {
                os_log_error(OS_LOG_DEFAULT,
                             "[AutoFill] Failed to obtain service endpoint from "
                             "helper: %{public}@",
                             error);
                [self resolveServiceConnection];
                return;
            }

            self.xpcClient.connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
            self.xpcClient.connection.remoteObjectInterface = AutoFillXPCInterface();
            [self.xpcClient.connection setCodeSigningRequirement:CodeSigningRequirement(@APPLE_APP_IDENTIFIER)];
            [self.xpcClient.connection resume];

            [self resolveServiceConnection];
        }];
    }
    return self;
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    [self focusEmbeddedWidget];

    return;
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier*>*)serviceIdentifiers
{
    auto* widget =
        new CredentialListWidget(self.extensionContext, serviceIdentifiers, CredentialListWidget::Mode::Password);
    [self embedCredentialListWidget:widget];
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier*>*)serviceIdentifiers
                                 requestParameters:(ASPasskeyCredentialRequestParameters*)requestParameters
{
    auto* widget = new CredentialListWidget(self.extensionContext, requestParameters);
    [self embedCredentialListWidget:widget];
}

- (void)prepareOneTimeCodeCredentialListForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier*>*)serviceIdentifiers
{
    auto* widget =
        new CredentialListWidget(self.extensionContext, serviceIdentifiers, CredentialListWidget::Mode::TOTP);
    [self embedCredentialListWidget:widget];
}

- (void)prepareInterfaceForPasskeyRegistration:(id<ASCredentialRequest>)registrationRequest
{
    auto* widget = new PasskeyRegistrationWidget(self.extensionContext,
                                                 static_cast<ASPasskeyCredentialRequest*>(registrationRequest));
    __weak CredentialProviderViewController* weakSelf = self;
    widget->withServiceConnection = [weakSelf](void (^block)(NSXPCConnection*)) {
        [weakSelf withServiceConnection:block];
    };
    widget->onResizeRequested = [weakSelf, widget](QSize size) { [weakSelf resizeEmbeddedWidget:widget toSize:size]; };
    if (widget->start()) {
        [self embedQWidget:widget];
    }
}

- (void)prepareInterfaceToProvideCredentialForRequest:(id<ASCredentialRequest>)credentialRequest
{
    // With our UI showing, KeePassXC may ask for approval itself; fall back to
    // unlocking here if it can't provide the credential
    [self fetchCredentialForRequest:credentialRequest
                        interactive:YES
                              reply:^(id credential, NSError* error) {
                                  if (credential) {
                                      [self completeRequest:credentialRequest withCredential:credential];
                                  } else if ([self isCancelledError:error]) {
                                      [self exitCancelRequest];
                                  } else {
                                      dispatch_async(dispatch_get_main_queue(), ^{
                                          [self showConfirmationForRequest:credentialRequest];
                                      });
                                  }
                              }];
}

- (void)provideCredentialWithoutUserInteractionForRequest:(id<ASCredentialRequest>)credentialRequest
{
    [self fetchCredentialForRequest:credentialRequest
                        interactive:NO
                              reply:^(id credential, NSError* error) {
                                  if (credential) {
                                      [self completeRequest:credentialRequest withCredential:credential];
                                  } else if ([self isCancelledError:error]) {
                                      [self exitCancelRequest];
                                  } else {
                                      // Not open in KeePassXC, entry not found or approval required (401):
                                      // let the system show our UI
                                      [self exitWithUserInteractionRequired];
                                  }
                              }];
}

// A picked credential: try Touch ID with only the system prompt, and show the
// unlock UI if it isn't available, fails or is cancelled
- (void)showConfirmationForRequest:(id<ASCredentialRequest>)credentialRequest
{
    auto* widget = new ConfirmationWidget(self.extensionContext, credentialRequest);
    if (widget->tryQuickUnlock()) {
        return;
    }
    [self embedQWidget:widget];
}

// Unlock was cancelled in KeePassXC: honour that instead of showing our UI
- (BOOL)isCancelledError:(NSError*)error
{
    return IsAutoFillError(error, AutoFillErrorCancelled);
}

// Asks KeePassXC for the credential; replies (nil, nil) without a connection
- (void)fetchCredentialForRequest:(id<ASCredentialRequest>)credentialRequest
                      interactive:(BOOL)interactive
                            reply:(void (^)(id credential, NSError* error))reply
{
    [self withServiceConnection:^(NSXPCConnection* connection) {
        if (!connection) {
            reply(nil, nil);
            return;
        }
        id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError* _Nonnull error) {
            os_log_error(OS_LOG_DEFAULT,
                         "[AutoFill] AutoFill service connection error: %{public}@. Main app likely closed.",
                         error);
            reply(nil, error);
        }];

        switch (credentialRequest.type) {
        case ASCredentialRequestTypePassword: {
            [proxy fetchPasswordCredentialForIdentity:static_cast<ASPasswordCredentialIdentity*>(
                                                          credentialRequest.credentialIdentity)
                                          interactive:interactive
                                            withReply:^(ASPasswordCredential* credential, NSError* error) {
                                                reply(credential, error);
                                            }];
            break;
        }
        case ASCredentialRequestTypeOneTimeCode: {
            [proxy fetchOneTimeCodeForIdentity:static_cast<ASOneTimeCodeCredentialIdentity*>(
                                                   credentialRequest.credentialIdentity)
                                   interactive:interactive
                                     withReply:^(ASOneTimeCodeCredential* credential, NSError* error) {
                                         reply(credential, error);
                                     }];
            break;
        }
        case ASCredentialRequestTypePasskeyAssertion: {
            [proxy
                fetchPasskeyCredentialFromPasskeyRequest:static_cast<ASPasskeyCredentialRequest*>(credentialRequest)
                                             interactive:interactive
                                               withReply:^(ASPasskeyAssertionCredential* credential, NSError* error) {
                                                   reply(credential, error);
                                               }];
            break;
        }
        default:
            reply(nil, nil);
            break;
        }
    }];
}

- (void)completeRequest:(id<ASCredentialRequest>)credentialRequest withCredential:(id)credential
{
    switch (credentialRequest.type) {
    case ASCredentialRequestTypePassword:
        [self.extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
        break;
    case ASCredentialRequestTypeOneTimeCode:
        [self.extensionContext completeOneTimeCodeRequestWithSelectedCredential:credential completionHandler:nil];
        break;
    case ASCredentialRequestTypePasskeyAssertion:
        [self.extensionContext completeAssertionRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
        break;
    default:
        [self exitCancelRequest];
        break;
    }
}

// Runs block once the direct connection to KeePassXC is known (nil if the
// endpoint lookup failed), so early requests don't message a nil connection
- (void)withServiceConnection:(void (^)(NSXPCConnection* connection))block
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.serviceConnectionResolved) {
            block(self.xpcClient.connection);
            return;
        }
        if (!self.pendingConnectionBlocks) {
            self.pendingConnectionBlocks = [NSMutableArray array];
        }
        [self.pendingConnectionBlocks addObject:[block copy]];
    });
}

- (void)resolveServiceConnection
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.serviceConnectionResolved) {
            return;
        }
        self.serviceConnectionResolved = YES;
        NSArray* blocks = self.pendingConnectionBlocks;
        self.pendingConnectionBlocks = nil;
        for (void (^block)(NSXPCConnection*) in blocks) {
            block(self.xpcClient.connection);
        }
    });
}

- (void)embedQWidget:(QWidget*)widget
{
    widget->show();

    NSView* rootView = (__bridge NSView*)reinterpret_cast<void*>(widget->winId());

    [self.view addSubview:rootView];

    self.view.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.view.topAnchor constraintEqualToAnchor:rootView.topAnchor constant:0],
        [self.view.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor constant:0],
        [self.view.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor constant:0],
        [self.view.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor constant:0]
    ]];

    self.widthConstraint = [self.view.widthAnchor constraintEqualToConstant:rootView.frame.size.width];
    self.heightConstraint = [self.view.heightAnchor constraintEqualToConstant:rootView.frame.size.height];
    self.widthConstraint.active = YES;
    self.heightConstraint.active = YES;

    self.rootView = rootView;
    [self focusEmbeddedWidget];
}

// Qt only receives key events once its view is first responder; otherwise
// typing does nothing until the sheet is clicked
- (void)focusEmbeddedWidget
{
    if (self.rootView && self.view.window) {
        [self.view.window makeFirstResponder:self.rootView];
    }
}

- (void)embedCredentialListWidget:(CredentialListWidget*)widget
{
    __weak CredentialProviderViewController* weakSelf = self;
    widget->onResizeRequested = [weakSelf, widget](QSize size) { [weakSelf resizeEmbeddedWidget:widget toSize:size]; };
    [self embedQWidget:widget];
}

- (void)resizeEmbeddedWidget:(QWidget*)widget toSize:(QSize)size
{
    widget->resize(size);
    self.widthConstraint.constant = size.width();
    self.heightConstraint.constant = size.height();
}

- (void)exitWithUserInteractionRequired
{
    NSError* error = [NSError errorWithDomain:ASExtensionErrorDomain
                                         code:ASExtensionErrorCodeUserInteractionRequired
                                     userInfo:nil];
    [self.extensionContext cancelRequestWithError:error];
}

- (void)exitCancelRequest
{
    NSError* error = [NSError errorWithDomain:ASExtensionErrorDomain code:ASExtensionErrorCodeFailed userInfo:nil];
    [self.extensionContext cancelRequestWithError:error];
}

@end
