#include <AuthenticationServices/AuthenticationServices.h>

#include <QSharedPointer>
#include <QWidget>
#include <functional>

#include "core/Database.h"

#ifndef DATABASEUNLOCKWIDGET_H
#define DATABASEUNLOCKWIDGET_H

class DatabaseOpenWidget;
class QStackedWidget;
class QWidget;

// Resolves a single database path into an unlocked Database, offering
// Touch ID / Quick Unlock when available and falling back to the real
// DatabaseOpenWidget (password / key file / hardware key) otherwise.
//
// No Q_OBJECT/signals here: this header pulls in AuthenticationServices,
// and moc-generated code for it would be compiled as plain C++ (not
// Objective-C++), which fails to parse the ObjC framework headers. Callers
// set onUnlocked/onCancelled instead, matching the plain-callback style
// already used elsewhere in this extension (e.g. BrowserPasskeysConfirmationDialogV2).
class DatabaseUnlockWidget : public QWidget
{
public:
    explicit DatabaseUnlockWidget(const QString& dbPath, QWidget* parent = nullptr);
    ~DatabaseUnlockWidget() override;

    std::function<void(QSharedPointer<Database>)> onUnlocked;
    std::function<void()> onCancelled;

private:
    void setupQuickUnlock();
    void showPasswordEntry();
    void openWidgetFinished(bool accepted);

    QString m_dbPath;
    QSharedPointer<Database> m_db;
    LAContext* m_laContext;
    QStackedWidget* m_stack;
    QWidget* m_quickUnlockPage;
    DatabaseOpenWidget* m_openWidget;
};

#endif // DATABASEUNLOCKWIDGET_H
