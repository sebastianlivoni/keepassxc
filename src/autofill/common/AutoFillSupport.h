#ifndef KEEPASSXC_AUTOFILLSUPPORT_H
#define KEEPASSXC_AUTOFILLSUPPORT_H

// AutoFill uses macOS 15 APIs (one-time code identities, credential identity
// entries, SMAppService); on older macOS the feature is not started or shown
inline bool isAutoFillSupported()
{
    if (__builtin_available(macOS 15.0, *)) {
        return true;
    }
    return false;
}

#ifdef __OBJC__
#import <ServiceManagement/ServiceManagement.h>

// Login item that runs the AutoFill helper
inline SMAppService* autoFillHelperService()
{
    return [SMAppService agentServiceWithPlistName:@HELPER_APP_IDENTIFIER ".plist"];
}
#endif

#endif // KEEPASSXC_AUTOFILLSUPPORT_H
