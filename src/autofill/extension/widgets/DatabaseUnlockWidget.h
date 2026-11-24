#include <AuthenticationServices/AuthenticationServices.h>

#include <QSharedPointer>
#include <QWidget>
#include <functional>

#include "core/Database.h"

#ifndef DATABASEUNLOCKWIDGET_H
#define DATABASEUNLOCKWIDGET_H

class DatabaseOpenWidget;

// Unlocks a database with the main app's DatabaseOpenWidget; cancelling cancels the
// AutoFill request. Callers set onUnlocked (plain callbacks, no signals)
class DatabaseUnlockWidget : public QWidget
{
public:
    explicit DatabaseUnlockWidget(ASCredentialProviderExtensionContext* extensionContext,
                                  const QString& dbPath,
                                  QWidget* parent = nullptr);
    ~DatabaseUnlockWidget() override;

    std::function<void(QSharedPointer<Database>)> onUnlocked;

    // Runs Touch ID right away (only the system prompt); true if the database unlocked
    bool tryQuickUnlock();

private:
    void openWidgetFinished(bool accepted);
    void showNotSharedYet(const QString& dbPath);
    void cancelRequest();

    ASCredentialProviderExtensionContext* m_extensionContext;
    DatabaseOpenWidget* m_openWidget;
    bool m_unlocked = false;
};

#endif // DATABASEUNLOCKWIDGET_H
