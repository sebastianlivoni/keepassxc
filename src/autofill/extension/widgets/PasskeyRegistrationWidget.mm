#include "extension/widgets/PasskeyRegistrationWidget.h"

#include <QLayout>
#include <QPushButton>
#include <os/log.h>

#include "browser/BrowserPasskeysConfirmationDialog.h"
#include "common/AutoFillCredentials.h"
#include "common/AutoFillXPCProtocol.h"
#include "core/Config.h"
#include "core/Entry.h"
#include "core/Tools.h"
#include "extension/widgets/DatabasePickerWidget.h"
#include "extension/widgets/DatabaseUnlockWidget.h"

// No timeout comes with the request; 5 minutes like browsers' WebAuthn default
static const int PASSKEY_REGISTRATION_TIMEOUT_MS = 300000;

PasskeyRegistrationWidget::PasskeyRegistrationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                                     ASPasskeyCredentialRequest* request,
                                                     QWidget* parent)
    : QStackedWidget(parent)
    , m_extensionContext(extensionContext)
    , m_request(request)
{
    auto* identity = static_cast<ASPasskeyCredentialIdentity*>(request.credentialIdentity);
    m_relyingParty = QString::fromNSString(identity.relyingPartyIdentifier);
    m_username = QString::fromNSString(identity.userName);
    resize(480, 420);
}

bool PasskeyRegistrationWidget::start()
{
    const auto databasePaths = config()->getAllDatabaseFilePaths();
    if (databasePaths.isEmpty()) {
        cancel();
        return false;
    }

    if (databasePaths.size() == 1) {
        useDatabase(databasePaths.constBegin().value());
    } else {
        auto* picker = new DatabasePickerWidget(this);
        picker->onDatabaseChosen = [this](const QString& dbPath) { useDatabase(dbPath); };
        picker->onCancelled = [this]() { cancel(); };
        addWidget(picker);
        setCurrentWidget(picker);
    }
    return true;
}

// Database already unlocked in KeePassXC: register there over XPC (like
// assertion) instead of unlocking it again here
void PasskeyRegistrationWidget::useDatabase(const QString& path)
{
    // Copies for the async blocks below
    const QString dbPath = path;
    const QString dbUuid = config()->getAllDatabaseFilePaths().key(dbPath);
    withServiceConnection(^(NSXPCConnection* connection) {
        if (!connection || dbUuid.isEmpty()) {
            unlockInExtension(dbPath);
        } else {
            registerInKeePassXC(connection, dbUuid, dbPath);
        }
    });
}

void PasskeyRegistrationWidget::registerInKeePassXC(NSXPCConnection* connection,
                                                    const QString& uuid,
                                                    const QString& path)
{
    const QString dbUuid = uuid;
    const QString dbPath = path;
    // Falls back to unlocking here, e.g. when KeePassXC was closed
    id (^proxy)(void) = ^id {
        return [connection remoteObjectProxyWithErrorHandler:^(NSError* error) {
            os_log_error(OS_LOG_DEFAULT, "[AutoFill] AutoFill service connection error: %{public}@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                unlockInExtension(dbPath);
            });
        }];
    };

    [proxy()
        fetchExistingPasskeysForRegistrationRequest:m_request
                                       databaseUuid:dbUuid.toNSString()
                                          withReply:^(NSArray<NSArray<NSString*>*>* entries, NSError*) {
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  // Not open or locked in KeePassXC
                                                  if (!entries) {
                                                      unlockInExtension(dbPath);
                                                      return;
                                                  }
                                                  // Stand-ins for KeePassXC's entries, only for display and selection
                                                  // in the dialog
                                                  QList<Entry*> existingEntries;
                                                  for (NSArray<NSString*>* fields in entries) {
                                                      if (fields.count == 3) {
                                                          auto* entry = new Entry();
                                                          entry->QObject::setParent(this);
                                                          entry->setUuid(
                                                              Tools::hexToUuid(QString::fromNSString(fields[0])));
                                                          entry->setTitle(QString::fromNSString(fields[1]));
                                                          entry->setUsername(QString::fromNSString(fields[2]));
                                                          existingEntries.append(entry);
                                                      }
                                                  }
                                                  showRegistrationDialog(
                                                      existingEntries,
                                                      [this, proxy, dbUuid, dbPath](const QUuid& entryUuid) {
                                                          [proxy()
                                                              registerPasskeyForRequest:m_request
                                                                           databaseUuid:dbUuid.toNSString()
                                                                      existingEntryUuid:entryUuid.isNull()
                                                                                            ? @""
                                                                                            : Tools::uuidToHex(
                                                                                                  entryUuid)
                                                                                                  .toNSString()
                                                                              withReply:^(
                                                                                  ASPasskeyRegistrationCredential*
                                                                                      credential,
                                                                                  NSError* error) {
                                                                                  dispatch_async(
                                                                                      dispatch_get_main_queue(), ^{
                                                                                          // KeePassXC closed or locked
                                                                                          // the database since the
                                                                                          // dialog was shown: unlock
                                                                                          // here and show the dialog
                                                                                          // again from the database
                                                                                          // file
                                                                                          if (!credential
                                                                                              && IsAutoFillError(
                                                                                                  error,
                                                                                                  AutoFillErrorNotFound)) {
                                                                                              unlockInExtension(dbPath);
                                                                                              return;
                                                                                          }
                                                                                          complete(credential);
                                                                                      });
                                                                              }];
                                                      });
                                              });
                                          }];
}

void PasskeyRegistrationWidget::unlockInExtension(const QString& dbPath)
{
    auto* unlockWidget = new DatabaseUnlockWidget(m_extensionContext, dbPath, this);
    unlockWidget->onUnlocked = [this](QSharedPointer<Database> db) { registerLocally(db); };
    addWidget(unlockWidget);
    setCurrentWidget(unlockWidget);
    // Before embedding (single database) this sets the initial size
    resizeTo(size().expandedTo(unlockWidget->size()));
}

void PasskeyRegistrationWidget::registerLocally(QSharedPointer<Database> db)
{
    const auto existingEntries =
        AutoFillCredentials::searchEntries(db, m_relyingParty, /*passkeyOnly=*/true, /*totpOnly=*/false);
    showRegistrationDialog(existingEntries, [this, db](const QUuid& entryUuid) {
        Entry* existingEntry = entryUuid.isNull() ? nullptr : db->rootGroup()->findEntryByUuid(entryUuid);
        ASPasskeyCredentialIdentity* previousIdentity =
            existingEntry
                ? AutoFillCredentials::getPasskeyCredentialIdentityFromEntry(existingEntry, db->publicUuid())
                : nil;
        Entry* registeredEntry = nullptr;
        ASPasskeyRegistrationCredential* credential = AutoFillCredentials::createPasskeyRegistrationCredential(
            m_request, db, existingEntry, /*saveDatabase=*/true, &registeredEntry);
        if (!credential) {
            cancel();
            return;
        }

        // KeePassXC isn't involved here, so publish the new passkey ourselves; complete only
        // once the store is updated, since the extension may end right after
        ASPasskeyCredentialIdentity* identity =
            AutoFillCredentials::getPasskeyCredentialIdentityFromEntry(registeredEntry, db->publicUuid());
        void (^finish)(void) = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                complete(credential);
            });
        };
        void (^save)(void) = ^{
            if (!identity) {
                finish();
                return;
            }
            [ASCredentialIdentityStore.sharedStore
                saveCredentialIdentityEntries:@[ identity ]
                                   completion:^(BOOL success, NSError* error) {
                                       if (!success) {
                                           NSLog(@"[AutoFill] Failed to save passkey identity: %@", error);
                                       }
                                       finish();
                                   }];
        };
        if (!previousIdentity) {
            save();
            return;
        }
        [ASCredentialIdentityStore.sharedStore
            removeCredentialIdentityEntries:@[ previousIdentity ]
                                 completion:^(BOOL success, NSError* error) {
                                     if (!success) {
                                         NSLog(@"[AutoFill] Failed to remove replaced passkey identity: %@", error);
                                     }
                                     save();
                                 }];
    });
}

void PasskeyRegistrationWidget::showRegistrationDialog(const QList<Entry*>& existingEntries,
                                                       std::function<void(const QUuid&)> confirm)
{
    // The browser integration's dialog, embedded instead of shown as a window
    auto* dialog = new BrowserPasskeysConfirmationDialog();
    dialog->setWindowFlags(Qt::Widget);
    dialog->registerCredential(m_username, m_relyingParty, existingEntries, PASSKEY_REGISTRATION_TIMEOUT_MS);
    // "Add to existing entry" opens the browser's passkey importer, which isn't available here
    if (existingEntries.isEmpty()) {
        if (auto* updateButton = dialog->findChild<QPushButton*>("updateButton")) {
            updateButton->hide();
        }
    }
    QObject::connect(dialog, &QDialog::accepted, dialog, [this, dialog, confirm]() {
        if (!dialog->isPasskeyUpdated()) {
            confirm(QUuid());
        } else if (Entry* selectedEntry = dialog->getSelectedEntry()) {
            confirm(selectedEntry->uuid());
        } else {
            cancel();
        }
    });
    QObject::connect(dialog, &QDialog::rejected, dialog, [this]() { cancel(); });

    // Same size as the browser dialog: 400x274 from the .ui, or fixed to content
    dialog->layout()->activate();
    const QSize dialogSize = dialog->size().expandedTo(dialog->minimumSizeHint());
    addWidget(dialog);
    setCurrentWidget(dialog);

    // Drop picker/unlock pages so their minimum size doesn't block the resize;
    // deleteLater since we may be called from inside the unlock widget
    while (count() > 1) {
        QWidget* page = widget(0) == dialog ? widget(1) : widget(0);
        removeWidget(page);
        page->deleteLater();
    }
    layout()->activate();
    resizeTo(dialogSize);
}

void PasskeyRegistrationWidget::resizeTo(QSize size)
{
    resize(size);
    if (onResizeRequested) {
        onResizeRequested(size);
    }
}

void PasskeyRegistrationWidget::complete(ASPasskeyRegistrationCredential* credential)
{
    if (!credential) {
        cancel();
        return;
    }
    [m_extensionContext completeRegistrationRequestWithSelectedPasskeyCredential:credential completionHandler:nil];
}

void PasskeyRegistrationWidget::cancel()
{
    [m_extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                                                   code:ASExtensionErrorCodeFailed
                                                               userInfo:nil]];
}
