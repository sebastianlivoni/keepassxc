#include "extension/widgets/ConfirmationWidget.h"

#include "common/AutoFillCredentials.h"
#include "extension/widgets/DatabaseUnlockWidget.h"

#include <QVBoxLayout>
#include <os/log.h>

#include "core/Config.h"
#include "core/Database.h"
#include "core/Group.h"
#include "core/Tools.h"

ConfirmationWidget::ConfirmationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                       id<ASCredentialRequest> credentialRequest,
                                       QWidget* parent)
    : QWidget(parent)
    , m_extensionContext(extensionContext)
    , m_credentialRequest(credentialRequest)
    , m_unlockWidget(nullptr)
{

    NSString* recordIdentifier = m_credentialRequest.credentialIdentity.recordIdentifier;

    QUuid dbUuid;
    QUuid entryUuid;
    QString dbPath;
    if (recordIdentifier.length > 0
        && AutoFillCredentials::parseRecordIdentifier(recordIdentifier, dbUuid, entryUuid)) {
        dbPath = config()->getDatabaseFilePath(Tools::uuidToHex(dbUuid));
    }

    // Only check the path is known; the file itself is reached through
    // KeePassXC's bookmark in DatabaseUnlockWidget (the sandbox hides it before that)
    if (dbPath.isEmpty()) {
        os_log_error(OS_LOG_DEFAULT, "[AutoFill] No database file for record identifier: %{public}@", recordIdentifier);
        // The suggestion points at a database KeePassXC no longer knows: remove it
        removeStaleIdentityAndExit();
        return;
    }

    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);

    m_unlockWidget = new DatabaseUnlockWidget(m_extensionContext, dbPath, this);
    m_unlockWidget->onUnlocked = [this](QSharedPointer<Database> db) {
        m_db = db;
        completeRequest();
    };
    mainLayout->addWidget(m_unlockWidget);

    setLayout(mainLayout);
    resize(m_unlockWidget->size());
    setWindowTitle(tr("Confirm Access"));
    // Shown when embedded, so a Touch ID attempt first shows only the system prompt
}

void ConfirmationWidget::completeRequest()
{
    NSString* recordIdentifier = m_credentialRequest.credentialIdentity.recordIdentifier;
    id credential = nil;
    switch (m_credentialRequest.type) {
    case ASCredentialRequestTypePassword:
        credential = AutoFillCredentials::getPasswordCredentialFromIdentity(recordIdentifier, m_db);
        break;
    case ASCredentialRequestTypeOneTimeCode:
        credential = AutoFillCredentials::getOneTimeCodeCredentialFromIdentity(recordIdentifier, m_db);
        break;
    case ASCredentialRequestTypePasskeyAssertion:
        credential = AutoFillCredentials::getPasskeyCredentialFromPasskeyRequest(
            static_cast<ASPasskeyCredentialRequest*>(m_credentialRequest), m_db);
        break;
    default:
        break;
    }
    if (!credential) {
        exitWithoutCredential();
        return;
    }

    switch (m_credentialRequest.type) {
    case ASCredentialRequestTypePassword:
        [m_extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
        break;
    case ASCredentialRequestTypeOneTimeCode:
        [m_extensionContext completeOneTimeCodeRequestWithSelectedCredential:credential completionHandler:nil];
        break;
    default:
        [m_extensionContext completeAssertionRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
        break;
    }
}

bool ConfirmationWidget::tryQuickUnlock()
{
    return m_unlockWidget && m_unlockWidget->tryQuickUnlock();
}

void ConfirmationWidget::exitWithoutCredential()
{
    QUuid dbUuid;
    QUuid entryUuid;
    NSString* recordIdentifier = m_credentialRequest.credentialIdentity.recordIdentifier;
    const bool entryGone = m_db && m_db->rootGroup()
                           && AutoFillCredentials::parseRecordIdentifier(recordIdentifier, dbUuid, entryUuid)
                           && !AutoFillCredentials::entryForRecord(recordIdentifier, m_db);

    if (entryGone) {
        removeStaleIdentityAndExit();
    } else {
        exitCancelRequest();
    }
}

void ConfirmationWidget::removeStaleIdentityAndExit()
{
    ASCredentialProviderExtensionContext* context = m_extensionContext;
    id<ASCredentialIdentity> identity = m_credentialRequest.credentialIdentity;
    void (^cancel)(void) = ^{
        [context cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                                            code:ASExtensionErrorCodeCredentialIdentityNotFound
                                                        userInfo:nil]];
    };

    if (!identity) {
        dispatch_async(dispatch_get_main_queue(), cancel);
        return;
    }

    // Cancel only after the removal finished; the extension may end right after
    [ASCredentialIdentityStore.sharedStore
        removeCredentialIdentityEntries:@[ identity ]
                             completion:^(BOOL success, NSError* error) {
                                 if (!success) {
                                     NSLog(@"[AutoFill] Failed to remove stale identity: %@", error);
                                 }
                                 dispatch_async(dispatch_get_main_queue(), cancel);
                             }];
}

void ConfirmationWidget::exitCancelRequest()
{
    NSError* error = [NSError errorWithDomain:ASExtensionErrorDomain code:ASExtensionErrorCodeFailed userInfo:nil];
    [m_extensionContext cancelRequestWithError:error];
}
