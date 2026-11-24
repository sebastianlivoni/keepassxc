#include <AuthenticationServices/AuthenticationServices.h>

#include <QList>
#include <QSharedPointer>
#include <QStringList>
#include <QWidget>
#include <functional>

#include "core/Database.h"

#ifndef CREDENTIALLISTWIDGET_H
#define CREDENTIALLISTWIDGET_H

class QStackedWidget;
class QLabel;
class EntryView;
class Entry;

// Credential picker for password, passkey and one-time code lists; with no recordIdentifier
// it picks a database (if several), unlocks it, then lets the user pick an entry
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
                                  ASPasskeyCredentialRequestParameters* passkeyRequestParameters,
                                  QWidget* parent = nullptr);

    // Set by the embedder to resize the extension view along with this widget
    std::function<void(QSize)> onResizeRequested;

private:
    void resolveDatabase();
    void useDatabasePath(const QString& dbPath);
    void showEntryList();
    void populateEntries(const QList<Entry*>& entries);
    void showEntries(bool all);
    void confirmSelection();
    void completeWithEntry(Entry* entry);
    void exitCancelRequest();

    ASCredentialProviderExtensionContext* m_extensionContext;
    ASPasskeyCredentialRequestParameters* m_passkeyRequestParameters;
    Mode m_mode;
    QStringList m_siteUrls;
    QString m_siteName;

    QSharedPointer<Database> m_db;

    QStackedWidget* m_stack;
    QWidget* m_entryPage;
    EntryView* m_entryView;
    QLabel* m_emptyLabel;
};

#endif // CREDENTIALLISTWIDGET_H
