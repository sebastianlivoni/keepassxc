#include <Foundation/Foundation.h>
#include <AppKit/AppKit.h>
#include <AuthenticationServices/AuthenticationServices.h>

@interface AutoFillViewController : NSViewController

@property (nonatomic, strong, readonly) ASCredentialProviderExtensionContext *extensionContext;

- (instancetype)initWithExtensionContext:(ASCredentialProviderExtensionContext *)extensionContext;

@end