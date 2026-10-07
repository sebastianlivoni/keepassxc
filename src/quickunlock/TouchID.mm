/*
*  Copyright (C) 2025 KeePassXC Team <team@keepassxc.org>
*
*  This program is free software: you can redistribute it and/or modify
*  it under the terms of the GNU General Public License as published by
*  the Free Software Foundation, either version 2 or (at your option)
*  version 3 of the License.
*
*  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*
*  You should have received a copy of the GNU General Public License
*  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "quickunlock/TouchID.h"

#include "crypto/Random.h"
#include "crypto/SymmetricCipher.h"
#include "crypto/CryptoHash.h"
#include "config-keepassx.h"

#include <botan/mem_ops.h>

#include <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <LocalAuthentication/LocalAuthentication.h>
#include <Security/Security.h>

#include <QCoreApplication>
#include <QString>

#define TOUCH_ID_ENABLE_DEBUG_LOGS() 0
#if TOUCH_ID_ENABLE_DEBUG_LOGS()
#define debug(...) qWarning(__VA_ARGS__)
#else
inline void debug(const char *message, ...)
{
   Q_UNUSED(message);
}
#endif

inline std::string StatusToErrorMessage(OSStatus status)
{
   CFStringRef text = SecCopyErrorMessageString(status, NULL);
   if (!text) {
      return std::to_string(status);
   }

   auto msg = CFStringGetCStringPtr(text, kCFStringEncodingUTF8);
   std::string result;
   if (msg) {
       result = msg;
   }
   CFRelease(text);
   return result;
}

inline void LogStatusError(const char *message, OSStatus status)
{
   if (!status) {
      return;
   }

   std::string msg = StatusToErrorMessage(status);
   debug("%s: %s", message, msg.c_str());
}

inline CFMutableDictionaryRef makeDictionary() {
   return CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

//! Try to delete an existing keychain entry and its Secure Enclave key
void TouchID::deleteKeyEntry(const QString& accountName)
{
   NSString* nsAccountName = accountName.toNSString(); // The NSString is released by Qt

   // try to delete an existing entry
   CFMutableDictionaryRef query = makeDictionary();
   CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
   CFDictionarySetValue(query, kSecAttrAccount, (__bridge CFStringRef) nsAccountName);
   CFDictionarySetValue(query, kSecReturnData, kCFBooleanFalse);
   CFDictionarySetValue(query, kSecUseDataProtectionKeychain, kCFBooleanTrue);

   // get data from the KeyChain
   OSStatus status = SecItemDelete(query);
   LogStatusError("TouchID::deleteKeyEntry - Status deleting existing entry", status);
   CFRelease(query);

   // deleting the SE key renders any leftover ciphertext useless
   NSData* tag = [nsAccountName dataUsingEncoding:NSUTF8StringEncoding];
   query = makeDictionary();
   CFDictionarySetValue(query, kSecClass, kSecClassKey);
   CFDictionarySetValue(query, kSecAttrApplicationTag, (__bridge CFDataRef)tag);
   CFDictionarySetValue(query, kSecUseDataProtectionKeychain, kCFBooleanTrue);
   status = SecItemDelete(query);
   LogStatusError("TouchID::deleteKeyEntry - Status deleting Secure Enclave key", status);
   CFRelease(query);
}

static const SecKeyAlgorithm kWrapAlgorithm = kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM;

static const QString kKeyNamePrefix = QStringLiteral("KeepassXC_TouchID_Keys_");

QString TouchID::databaseKeyName(const QUuid& dbUuid)
{
    return kKeyNamePrefix + dbUuid.toString();
}

QString TouchID::errorString() const
{
    return m_error;
}

//! Delete every stored quick unlock key and its Secure Enclave key (only our own "KeepassXC_TouchID_Keys_" items)
void TouchID::reset()
{
    CFMutableDictionaryRef query = makeDictionary();
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecReturnAttributes, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitAll);
    CFDictionarySetValue(query, kSecUseDataProtectionKeychain, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecUseAuthenticationUI, kSecUseAuthenticationUIFail);

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, &result);
    CFRelease(query);
    if (status != errSecSuccess || !result) {
        if (status != errSecItemNotFound) {
            LogStatusError("TouchID::reset - Status listing entries", status);
        }
        return;
    }

    NSArray* items = (__bridge NSArray*)result;
    for (NSDictionary* item in items) {
        NSString* account = item[(__bridge NSString*)kSecAttrAccount];
        if (account && QString::fromNSString(account).startsWith(kKeyNamePrefix)) {
            deleteKeyEntry(QString::fromNSString(account));
        }
    }
    CFRelease(result);
}

bool TouchID::setKey(const QUuid& dbUuid, const QByteArray& passwordKey, const bool ignoreTouchID)
{
    if (passwordKey.isEmpty()) {
        debug("TouchID::setKey - illegal arguments");
        return false;
    }


    const QString keyName = databaseKeyName(dbUuid);

    deleteKeyEntry(keyName); // Try to delete the existing key entry

    // prepare adding secure entry to the macOS KeyChain
    CFErrorRef error = NULL;

    // We need both runtime and compile time checks here to solve the following problems:
    // - Not all flags are available in all OS versions, so we have to check it at compile time
    // - Requesting Biometry/TouchID/DevicePassword when to fingerprint sensor is available will result in runtime error
    SecAccessControlCreateFlags accessControlFlags = 0;
#if XC_COMPILER_SUPPORT(APPLE_BIOMETRY)
    // Needs a special check to work with SecItemAdd, when TouchID is not enrolled and the flag
    // is set, the method call fails with an error. But we want to still set this flag if TouchID is
    // enrolled but temporarily unavailable due to closed lid
    //
    // At least on a Hackintosh the enrolled-check does not work, there LAErrorBiometryNotAvailable gets returned instead of
    // LAErrorBiometryNotEnrolled.
    //
    // That's kinda unfortunate, because now you cannot know for sure if TouchID hardware is either temporarily unavailable or not present
    // at all, because LAErrorBiometryNotAvailable is used for both cases.
    //
    // So to make quick unlock fallbacks possible on these machines you have to try to save the key a second time without this flag, if the
    // first try fails with an error.
    if (!ignoreTouchID) {
        // Prefer the non-deprecated flag when available
        accessControlFlags = kSecAccessControlBiometryCurrentSet;
    }
#elif XC_COMPILER_SUPPORT(TOUCH_ID)
    if (!ignoreTouchID) {
        accessControlFlags = kSecAccessControlTouchIDCurrentSet;
    }
#endif

#if XC_COMPILER_SUPPORT(WATCH_UNLOCK)
      accessControlFlags = accessControlFlags | kSecAccessControlOr | kSecAccessControlWatch;
#endif

#if XC_COMPILER_SUPPORT(TOUCH_ID)
   if (isPasswordFallbackPossible()) {
       accessControlFlags = accessControlFlags | kSecAccessControlOr | kSecAccessControlDevicePasscode;
   }
#endif

   // the private key never leaves the Secure Enclave; using it requires the flags above
   accessControlFlags = accessControlFlags | kSecAccessControlPrivateKeyUsage;

   SecAccessControlRef sacObject = SecAccessControlCreateWithFlags(
       kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, accessControlFlags, &error);

   if (sacObject == NULL || error != NULL) {
       NSError* e = (__bridge NSError*)error;
       debug("TouchID::setKey - Error creating security flags: %s", e.localizedDescription.UTF8String);
       if (error) {
           CFRelease(error);
       }
       return false;
   }

    NSString *accountName = keyName.toNSString(); // The NSString is released by Qt
    NSData* tag = [accountName dataUsingEncoding:NSUTF8StringEncoding];

    // one P-256 Secure Enclave key per database, stored in the default (shared) access group
    NSDictionary* keyAttributes = @{
        (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeySizeInBits : @256,
        (id)kSecAttrTokenID : (id)kSecAttrTokenIDSecureEnclave,
        (id)kSecUseDataProtectionKeychain : @YES,
        (id)kSecPrivateKeyAttrs : @{
            (id)kSecAttrIsPermanent : @YES,
            (id)kSecAttrApplicationTag : tag,
            (id)kSecAttrAccessControl : (__bridge id)sacObject,
        },
    };

    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)keyAttributes, &error);
    CFRelease(sacObject);
    if (!privateKey) {
        NSError* e = (__bridge NSError*)error;
        debug("TouchID::setKey - Error creating Secure Enclave key: %s", e.localizedDescription.UTF8String);
        if (error) {
            CFRelease(error);
        }
        return false;
    }

    // encrypting only needs the public key, so no authentication prompt here
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    CFRelease(privateKey);
    if (!publicKey || !SecKeyIsAlgorithmSupported(publicKey, kSecKeyOperationTypeEncrypt, kWrapAlgorithm)) {
        debug("TouchID::setKey - Secure Enclave public key unusable");
        if (publicKey) {
            CFRelease(publicKey);
        }
        deleteKeyEntry(keyName);
        return false;
    }

    // kCFAllocatorNull: the buffer stays owned (and scrubbed) by the caller
    auto keyData = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
                                               reinterpret_cast<const UInt8*>(passwordKey.constData()),
                                               passwordKey.length(),
                                               kCFAllocatorNull);
    CFDataRef wrappedKey = SecKeyCreateEncryptedData(publicKey, kWrapAlgorithm, keyData, &error);
    CFRelease(keyData);
    CFRelease(publicKey);
    if (!wrappedKey) {
        NSError* e = (__bridge NSError*)error;
        debug("TouchID::setKey - Error wrapping key: %s", e.localizedDescription.UTF8String);
        if (error) {
            CFRelease(error);
        }
        deleteKeyEntry(keyName);
        return false;
    }

    // the ciphertext is useless without the Secure Enclave key, so it needs no ACL of its own
    CFMutableDictionaryRef attributes = makeDictionary();
    CFDictionarySetValue(attributes, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(attributes, kSecAttrAccount, (__bridge CFStringRef) accountName);
    CFDictionarySetValue(attributes, kSecValueData, wrappedKey);
    CFDictionarySetValue(attributes, kSecAttrSynchronizable, kCFBooleanFalse);
    CFDictionarySetValue(attributes, kSecUseDataProtectionKeychain, kCFBooleanTrue);
    CFDictionarySetValue(attributes, kSecAttrAccessible, kSecAttrAccessibleWhenUnlockedThisDeviceOnly);

    // add to KeyChain
    OSStatus status = SecItemAdd(attributes, NULL);
    LogStatusError("TouchID::setKey - Status adding new entry", status);

    CFRelease(attributes);
    CFRelease(wrappedKey);

    if (status != errSecSuccess) {
        deleteKeyEntry(keyName);
        return false;
    }

    debug("TouchID::setKey - Success!");
    return true;
}

/**
 * Encrypts the PasswordKey with a per-database Secure Enclave key (ECIES) and stores
 * only the ciphertext in the KeyChain. Decryption runs inside the Secure Enclave
 * after TouchID, Apple Watch or device password authentication.
 */
bool TouchID::setKey(const QUuid& dbUuid, const QByteArray& passwordKey)
{
    if (!setKey(dbUuid,passwordKey, false)) {
        debug("TouchID::setKey failed with error trying fallback method without TouchID flag");
        return setKey(dbUuid, passwordKey, true);
    } else {
        return true;
    }
}

/**
 * Checks if an encrypted PasswordKey is available for the given database, tries to
 * decrypt it using the Secure Enclave and if successful, returns it.
 */
bool TouchID::getKey(const QUuid& dbUuid, QByteArray& passwordKey)
{
    passwordKey.clear();
    m_error.clear();

    if (!hasKey(dbUuid)) {
        debug("TouchID::getKey - No stored key found");
        return false;
    }

    const QString keyName = databaseKeyName(dbUuid);
    NSString* accountName = keyName.toNSString(); // The NSString is released by Qt

    // fetch the ciphertext (no authentication needed)
    CFMutableDictionaryRef query = makeDictionary();
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrAccount, (__bridge CFStringRef) accountName);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecUseDataProtectionKeychain, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecUseAuthenticationUI, kSecUseAuthenticationUIFail);

    CFTypeRef wrappedKey = NULL;
    OSStatus status = SecItemCopyMatching(query, &wrappedKey);
    CFRelease(query);
    if (status != errSecSuccess || wrappedKey == NULL) {
        LogStatusError("TouchID::getKey - ciphertext query error", status);
        m_error = QObject::tr("No stored Quick Unlock key found.");
        return false;
    }

    // fetch a reference to the Secure Enclave key; authentication happens on decrypt
    LAContext* context = [[LAContext alloc] init];
    context.localizedReason =
        QCoreApplication::translate("DatabaseOpenWidget", "authenticate to access the database").toNSString();

    query = makeDictionary();
    CFDictionarySetValue(query, kSecClass, kSecClassKey);
    CFDictionarySetValue(query, kSecAttrKeyClass, kSecAttrKeyClassPrivate);
    CFDictionarySetValue(
        query, kSecAttrApplicationTag, (__bridge CFDataRef)[accountName dataUsingEncoding:NSUTF8StringEncoding]);
    CFDictionarySetValue(query, kSecReturnRef, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecUseDataProtectionKeychain, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecUseAuthenticationContext, (__bridge CFTypeRef)context);
    CFDictionarySetValue(query, kSecUseAuthenticationUI, kSecUseAuthenticationUIAllow);
    [context release];

    CFTypeRef keyRef = NULL;
    status = SecItemCopyMatching(query, &keyRef);
    CFRelease(query);
    SecKeyRef privateKey = (SecKeyRef)keyRef;
    if (status != errSecSuccess || privateKey == NULL) {
        LogStatusError("TouchID::getKey - Secure Enclave key query error", status);
        CFRelease(wrappedKey);
        // ciphertext without its key is useless (e.g. legacy entry)
        deleteKeyEntry(keyName);
        m_error = QObject::tr("Quick Unlock key is missing, please unlock with your credentials.");
        return false;
    }

    // decrypt inside the Secure Enclave, this triggers the authentication prompt
    CFErrorRef error = NULL;
    CFDataRef plainKey =
        SecKeyCreateDecryptedData(privateKey, kWrapAlgorithm, static_cast<CFDataRef>(wrappedKey), &error);
    CFRelease(privateKey);
    CFRelease(wrappedKey);

    if (!plainKey) {
        CFIndex code = error ? CFErrorGetCode(error) : 0;
        bool laDomain = error && [[(__bridge NSError*)error domain] isEqualToString:LAErrorDomain];
        if (error) {
            CFRelease(error);
        }
        if (code == errSecUserCanceled
            || (laDomain && (code == LAErrorUserCancel || code == LAErrorAppCancel || code == LAErrorSystemCancel))) {
            // user canceled the authentication, return true with empty key
            debug("TouchID::getKey - User canceled authentication");
            return true;
        }
        debug("TouchID::getKey - decrypt error: %ld", static_cast<long>(code));
        m_error = QObject::tr("Quick Unlock authentication failed.");
        return false;
    }

    passwordKey = QByteArray(reinterpret_cast<const char*>(CFDataGetBytePtr(plainKey)), CFDataGetLength(plainKey));
    Botan::secure_scrub_memory(const_cast<UInt8*>(CFDataGetBytePtr(plainKey)), CFDataGetLength(plainKey));
    CFRelease(plainKey);

    return true;
}

bool TouchID::hasKey(const QUuid& dbUuid) const
{
    const QString keyName = databaseKeyName(dbUuid);
    NSString* accountName = keyName.toNSString();

    auto query =
        CFDictionaryCreateMutable(nullptr, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrAccount, (__bridge CFStringRef)accountName);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanFalse);
    CFDictionarySetValue(query, kSecUseDataProtectionKeychain, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecUseAuthenticationUI, kSecUseAuthenticationUIFail);

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, &result);

    if (result) {
        CFRelease(result);
    }
    CFRelease(query);

    return status == errSecInteractionNotAllowed || status == errSecSuccess;
}

// TODO: Both functions below should probably handle the returned errors to
// provide more information on availability. E.g.: the closed laptop lid results
// in an error (because touch id is not unavailable). That error could be
// displayed to the user when we first check for availability instead of just
// hiding the checkbox.

//! @return true if Apple Watch is available for authentication.
bool TouchID::isWatchAvailable()
{
#if XC_COMPILER_SUPPORT(WATCH_UNLOCK)
   @try {
      LAContext *context = [[LAContext alloc] init];

      LAPolicy policyCode = LAPolicyDeviceOwnerAuthenticationWithWatch;
      NSError *error;

      bool canAuthenticate = [context canEvaluatePolicy:policyCode error:&error];
      [context release];
      if (error) {
         debug("Apple Wach available: %d (%ld / %s / %s)", canAuthenticate,
               (long)error.code, error.description.UTF8String,
               error.localizedDescription.UTF8String);
      } else {
          debug("Apple Wach available: %d", canAuthenticate);
      }
      return canAuthenticate;
   } @catch (NSException *) {
      return false;
   }
#else
   return false;
#endif
}

//! @return true if Touch ID is available for authentication.
bool TouchID::isTouchIdAvailable()
{
#if XC_COMPILER_SUPPORT(TOUCH_ID)
   @try {
      LAContext *context = [[LAContext alloc] init];

      LAPolicy policyCode = LAPolicyDeviceOwnerAuthenticationWithBiometrics;
      NSError *error;

      bool canAuthenticate = [context canEvaluatePolicy:policyCode error:&error];
      [context release];
      if (error) {
         debug("Touch ID available: %d (%ld / %s / %s)", canAuthenticate,
               (long)error.code, error.description.UTF8String,
               error.localizedDescription.UTF8String);
      } else {
          debug("Touch ID available: %d", canAuthenticate);
      }
      return canAuthenticate;
   } @catch (NSException *) {
      return false;
   }
#else
   return false;
#endif
}

bool TouchID::isPasswordFallbackPossible()
{
#if XC_COMPILER_SUPPORT(TOUCH_ID)
    @try {
        LAContext *context = [[LAContext alloc] init];

        LAPolicy policyCode = LAPolicyDeviceOwnerAuthentication;
        NSError *error;

        bool canAuthenticate = [context canEvaluatePolicy:policyCode error:&error];
        [context release];
        if (error) {
            debug("Password fallback available: %d (%ld / %s / %s)", canAuthenticate,
                  (long)error.code, error.description.UTF8String,
                  error.localizedDescription.UTF8String);
        } else {
            debug("Password fallback available: %d", canAuthenticate);
        }
        return canAuthenticate;
    } @catch (NSException *) {
        return false;
    }
#else
    return false;
#endif
}

//! @return true if either TouchID or Apple Watch is available at the moment.
bool TouchID::isAvailable() const
{
   // note: we cannot cache the check results because the configuration
   // is dynamic in its nature. User can close the laptop lid or take off
   // the watch, thus making one (or both) of the authentication types unavailable.
   return  isWatchAvailable() || isTouchIdAvailable() || isPasswordFallbackPossible();
}

/**
 * Resets the inner state either for all or for the given database
 */
void TouchID::reset(const QUuid& dbUuid)
{
    if (!dbUuid.isNull()) {
        deleteKeyEntry(databaseKeyName(dbUuid));
    }
}
