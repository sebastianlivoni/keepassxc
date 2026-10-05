#include <AuthenticationServices/AuthenticationServices.h>

#include <QSharedPointer>
#include <QStackedWidget>
#include <functional>

#include "core/Database.h"

#ifndef PASSKEYREGISTRATIONWIDGET_H
#define PASSKEYREGISTRATIONWIDGET_H

class Entry;

// Registers a new passkey: in KeePassXC over XPC if it has the database unlocked,
// otherwise after unlocking the database here. Plain callbacks, like DatabaseUnlockWidget
class PasskeyRegistrationWidget : public QStackedWidget
{
public:
    explicit PasskeyRegistrationWidget(ASCredentialProviderExtensionContext* extensionContext,
                                       ASPasskeyCredentialRequest* request,
                                       QWidget* parent = nullptr);

    // Runs block with the connection to KeePassXC (nil without one)
    std::function<void(void (^)(NSXPCConnection*))> withServiceConnection;
    std::function<void(QSize)> onResizeRequested;

    // False if there is no AutoFill database (the request is then cancelled)
    bool start();

private:
    void useDatabase(const QString& dbPath);
    void registerInKeePassXC(NSXPCConnection* connection, const QString& dbUuid, const QString& dbPath);
    void unlockInExtension(const QString& dbPath);
    void registerLocally(QSharedPointer<Database> db);
    // confirm(existingEntryUuid) registers the passkey; a null UUID creates a new entry
    void showRegistrationDialog(const QList<Entry*>& existingEntries, std::function<void(const QUuid&)> confirm);
    void resizeTo(QSize size);
    void complete(ASPasskeyRegistrationCredential* credential);
    void cancel();

    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequest* m_request;
    QString m_relyingParty;
    QString m_username;
};

#endif // PASSKEYREGISTRATIONWIDGET_H
