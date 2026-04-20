//
//  CredentialProviderViewController.h
//  lol
//
//  Created by Sebastian Livoni on 31/01/2025.
//

#include <AuthenticationServices/AuthenticationServices.h>

#ifdef __OBJC__
#include "rendezvous/AutoFillXPCServiceClient.h"
#endif

@interface CredentialProviderViewController : ASCredentialProviderViewController

@property(nonatomic, strong) AutoFillXPCServiceClient *xpcService;

@end
