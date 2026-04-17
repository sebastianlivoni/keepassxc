#ifndef KEEPASSX_AUTOFILLSERVICEV2_H
#define KEEPASSX_AUTOFILLSERVICEV2_H

#include "AutoFillService.h"

class AutoFillServiceV2 : public AutoFillService {
public:
    static AutoFillServiceV2 *instance();  // was under private by mistake

    void start();
    void getMessage(void (^reply)(NSString *__strong, NSError *__strong));
    void fetchPasswordCredentialForRecordIdentifier(
        NSString *recordIdentifier,
        void (^reply)(NSString *__strong username, NSString *__strong password,
                      NSError *__strong error));
    void fetchOneTimeCodeForRecordIdentifier(
        NSString *recordIdentifier,
        void (^reply)(NSString *__strong code, NSError *__strong error));
    void fetchPasskeyCredentialFromPasskeyRequest(
        ASPasskeyCredentialRequest *request,
        void (^reply)(ASPasskeyAssertionCredential *__strong credential, NSError *__strong error));

private:
#ifdef __OBJC__
    __strong AutoFillXPCService *m_xpcService;
#endif
};

// Must be outside the class body
static inline AutoFillServiceV2 *autoFillServiceV2() {
    return AutoFillServiceV2::instance();
}

#endif // KEEPASSX_AUTOFILLSERVICEV2_H
