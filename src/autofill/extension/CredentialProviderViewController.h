#include <AuthenticationServices/AuthenticationServices.h>

#ifdef __OBJC__
#include "extension/AutoFillXPCClient.h"
#endif

@interface CredentialProviderViewController : ASCredentialProviderViewController

@property(nonatomic, strong) AutoFillXPCClient* xpcClient;

@end
