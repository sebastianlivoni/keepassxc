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

#endif // KEEPASSXC_AUTOFILLSUPPORT_H
