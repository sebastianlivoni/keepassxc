#include <AuthenticationServices/AuthenticationServices.h>

#include <QList>
#include <QSharedPointer>
#include <QWidget>

#include "core/Database.h"

#ifndef CREDENTIALLISTWIDGET_H
#define CREDENTIALLISTWIDGET_H

class QStackedWidget;
class QListWidget;
class Entry;

// Full credential picker shown for prepareCredentialListForServiceIdentifiers:
// (password), its passkey variant, and prepareOneTimeCodeCredentialListForServiceIdentifiers:.
// Unlike ConfirmationWidget's flow, the OS gives us no recordIdentifier here,
// so we resolve which database to search (picker if more than one is
// registered), unlock it, then search + let the user pick an entry.
class CredentialListWidget : public QWidget
{
public:
    enum class Mode
    {
        Password,
        TOTP,
        PasskeyAssertion
    };

    explicit CredentialListWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  NSArray<ASCredentialServiceIdentifier*>* serviceIdentifiers,
                                  Mode mode,
                                  QWidget* parent = nullptr);
    explicit CredentialListWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  NSArray<ASCredentialServiceIdentifier*>* serviceIdentifiers,
                                  ASPasskeyCredentialRequestParameters* passkeyRequestParameters,
                                  QWidget* parent = nullptr);

private:
    void resolveDatabase();
    void useDatabasePath(const QString& dbPath);
    void showEntryList();
    void populateEntries(const QList<Entry*>& entries);
    void showAllEntries();
    void confirmSelection();
    void completeWithEntry(Entry* entry);
    void exitCancelRequest();

    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequestParameters* m_passkeyRequestParameters;
    Mode m_mode;
    QString m_siteUrl;

    QSharedPointer<Database> m_db;
    QList<Entry*> m_entries;

    QStackedWidget* m_stack;
    QWidget* m_entryPage;
    QListWidget* m_entryListView;
};

#endif // CREDENTIALLISTWIDGET_H
